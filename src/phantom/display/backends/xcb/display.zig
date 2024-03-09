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
    return .{
        .allocator = alloc,
        .kind = kind,
        .connection = conn,
        .setup = conn.getSetup(),
        .screenId = screenId,
    };
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

inline fn getColorFormatFromVisualChannel(visual: *const xcb.xproto.VISUALTYPE, comptime field: []const u8) struct { u8, u8 } {
    return .{ @ctz(@field(visual, field ++ "_mask")), @popCount(@field(visual, field ++ "_mask")) };
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
