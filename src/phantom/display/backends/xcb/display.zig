const std = @import("std");
const Allocator = std.mem.Allocator;
const phantom = @import("phantom");
const Output = @import("output.zig");
const xcb = @import("xcb");
const vizops = @import("vizops");
const Self = @This();

allocator: Allocator,
kind: phantom.display.Base.Kind,
connection: *xcb.Connection,
setup: *const xcb.xproto.Setup,
screenId: c_int,

pub fn init(alloc: Allocator, kind: phantom.display.Base.Kind) !Self {
    var screenId: c_int = 0;
    const conn = try xcb.Connection.connect(null, &screenId);

    var self = Self{
        .allocator = alloc,
        .kind = kind,
        .connection = conn,
        .setup = conn.getSetup(),
        .screenId = screenId,
    };

    if (kind == .compositor) {
        const xscreen = try self.getXScreen();
        if (conn.requestCheck(xcb.xproto.changeWindowAttributes(conn, xscreen.root, 1 << 11, &[_:0]u32{1 << 15 | 1 << 20}))) |_| {
            return error.CompositorAlreadyActive;
        }
    }
    return self;
}

pub fn deinit(self: *Self) void {
    self.connection.disconnect();
}

pub fn display(self: *Self) phantom.display.Base {
    return .{
        .vtable = &.{
            .outputs = impl_outputs,
        },
        .type = @typeName(Self),
        .ptr = self,
        .kind = self.kind,
    };
}

pub fn getXScreen(self: *Self) !*const xcb.xproto.SCREEN {
    var iter = self.setup.rootsIterator();
    var i: usize = 0;
    while (iter.next()) |screen| : (i += 1) {
        if (i == self.screenId) return screen;
    }
    return error.ScreenNotFound;
}

pub fn getVisualInfo(self: *Self, depthId: u8, visualId: u32) !*const xcb.xproto.VISUALTYPE {
    const xscreen = try self.getXScreen();
    var depthIter = xscreen.allowedDepthsIterator();
    while (depthIter.next()) |depth| {
        if (depth.depth == depthId) {
            var visualIter = depth.visualsIterator();
            while (visualIter.next()) |visual| {
                if (visual.visual_id == visualId) {
                    return visual;
                }
            }
            return error.VisualNotFound;
        }
    }
    return error.DepthNotFound;
}

pub fn findVisualForColorFormat(self: *Self, colorFormat: vizops.color.fourcc.Value) !struct { u8, u32 } {
    const red = try getVisualChannelFromColorFormat(colorFormat, 0);
    const green = try getVisualChannelFromColorFormat(colorFormat, 1);
    const blue = try getVisualChannelFromColorFormat(colorFormat, 2);

    const xscreen = try self.getXScreen();
    var depthIter = xscreen.allowedDepthsIterator();
    while (depthIter.next()) |depth| {
        var visualIter = depth.visualsIterator();
        while (visualIter.next()) |visual| {
            if (visual.red_mask == red and visual.green_mask == green and visual.blue_mask == blue) {
                return .{ depth.depth, visual.visual_id };
            }
        }
    }
    return error.VisualNotFound;
}

inline fn getColorFormatFromVisualChannel(visual: *const xcb.xproto.VISUALTYPE, comptime field: []const u8) struct { u8, u8 } {
    return .{ @ctz(@field(visual, field ++ "_mask")), @popCount(@field(visual, field ++ "_mask")) };
}

inline fn getVisualChannelFromColorFormat(colorFormat: vizops.color.fourcc.Value, i: usize) !u32 {
    return switch (colorFormat) {
        .rgb => |rgb| (@as(u32, 1) << @as(u5, @intCast(rgb[i]))) - 1,
        .bgr => |bgr| (@as(u32, 1) << @as(u5, @intCast(bgr[2 - i]))) - 1,
        else => error.Unsupported,
    };
}

pub fn getColorFormatFromVisual(visual: *const xcb.xproto.VISUALTYPE) vizops.color.fourcc.Value {
    const red = getColorFormatFromVisualChannel(visual, "red");
    const green = getColorFormatFromVisualChannel(visual, "green");
    const blue = getColorFormatFromVisualChannel(visual, "blue");

    if (red[0] < blue[0]) {
        return .{ .rgb = .{ red[1], green[1], blue[1] } };
    }

    return .{ .bgr = .{ blue[1], green[1], red[1] } };
}

pub fn getProperty(self: *Self, win: xcb.xproto.WINDOW, typeName: []const u8, name: []const u8) !?[]const u8 {
    const typeAtom = try xcb.xproto.internAtom(self.connection, @intFromBool(false), @intCast(typeName.len), typeName.ptr).reply(self.connection);
    const nameAtom = try xcb.xproto.internAtom(self.connection, @intFromBool(false), @intCast(name.len), name.ptr).reply(self.connection);

    const prop = try xcb.xproto.getProperty(self.connection, @intFromBool(false), win, nameAtom.atom, typeAtom.atom, 0, 1).reply(self.connection);
    if (prop.valueLength() == 0) return null;

    if (prop.bytes_after > 0) {
        const prop2 = try xcb.xproto.getProperty(self.connection, @intFromBool(false), win, nameAtom.atom, typeAtom.atom, 0, 1 + prop.bytes_after).reply(self.connection);
        return prop2.value();
    }
    return prop.value();
}

fn impl_outputs(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Output) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var outputs = std.ArrayList(*phantom.display.Output).init(self.allocator);
    errdefer outputs.deinit();

    const xscreen = try self.getXScreen();
    const monitors = try xcb.randr.getMonitors(self.connection, xscreen.root, 0).reply(self.connection);
    var monitorsIter = monitors.monitorsIterator();

    while (monitorsIter.next()) |monitor| {
        for (monitor.outputs()) |output| {
            try outputs.append(&(try Output.new(self, output)).base);
        }
    }
    return outputs;
}
