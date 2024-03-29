const std = @import("std");
const vizops = @import("vizops");
const phantom = @import("phantom");
const Display = @import("display.zig");
const Surface = @import("surface.zig");
const xcb = @import("xcb");
const Self = @This();

base: phantom.display.Output,
display: *Display,
id: xcb.randr.OUTPUT,
scale: vizops.vector.Float32Vector2,

pub fn new(display: *Display, id: xcb.randr.OUTPUT) !*Self {
    const self = try display.allocator.create(Self);
    errdefer display.allocator.destroy(self);

    self.* = .{
        .base = .{
            .ptr = self,
            .vtable = &.{
                .surfaces = impl_surfaces,
                .createSurface = impl_create_surface,
                .info = impl_info,
                .updateInfo = impl_update_info,
                .deinit = impl_deinit,
            },
            .displayKind = display.kind,
            .type = @typeName(Self),
        },
        .display = display,
        .id = id,
        .scale = vizops.vector.Float32Vector2.init([_]f32{ 1.0, 1.0 }),
    };
    return self;
}

fn impl_surfaces(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Surface) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var surfaces = std.ArrayList(*phantom.display.Surface).init(self.display.allocator);
    errdefer surfaces.deinit();

    const outputInfo = try xcb.randr.getOutputInfo(self.display.connection, self.id, 0).reply(self.display.connection);
    const crtcInfo = try xcb.randr.getCrtcInfo(self.display.connection, outputInfo.crtc, 0).reply(self.display.connection);

    const xscreen = try self.display.getXScreen();
    const tree = try xcb.xproto.queryTree(self.display.connection, xscreen.root).reply(self.display.connection);
    for (tree.children()) |child| {
        const geom = try xcb.xproto.getGeometry(self.display.connection, .{ .window = child }).reply(self.display.connection);

        if (geom.x >= crtcInfo.x and (geom.x - @as(i16, @intCast(crtcInfo.width))) <= crtcInfo.width) {
            if (geom.y >= crtcInfo.y and (geom.y - @as(i16, @intCast(crtcInfo.height))) <= crtcInfo.height) {
                const surf = try Surface.new(self, child);
                errdefer surf.base.deinit();
                try surfaces.append(&surf.base);
            }
        }
    }
    return surfaces;
}

fn impl_create_surface(ctx: *anyopaque, kind: phantom.display.Surface.Kind, info: phantom.display.Surface.Info) anyerror!*phantom.display.Surface {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (kind == .output and self.display.kind == .client) {
        return error.NotSupported;
    }

    const xscreen = try self.display.getXScreen();
    const visual = if (info.colorFormat) |cf| try self.display.findVisualForColorFormat(cf) else .{ xscreen.root_depth, xscreen.root_visual };

    const wid = xcb.xproto.WINDOW{ .value = try self.display.connection.generateId() };
    if (self.display.connection.requestCheck(xcb.xproto.createWindow(
        self.display.connection,
        visual[0],
        wid,
        xscreen.root,
        0,
        0,
        @intCast(info.size.value[0]),
        @intCast(info.size.value[1]),
        0,
        1,
        visual[1],
        1 << 1 | 1 << 11,
        &[_:0]u32{ xscreen.black_pixel, 1 << 15 },
    ))) |err| {
        _ = err;
        return error.GenericError;
    }

    if (self.display.connection.requestCheck(xcb.xproto.mapWindow(self.display.connection, wid))) |err| {
        _ = err;
        return error.GenericError;
    }

    try self.display.connection.flush();

    const surf = try Surface.new(self, wid);
    errdefer surf.base.deinit();
    return &surf.base;
}

fn impl_info(ctx: *anyopaque) anyerror!phantom.display.Output.Info {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const xscreen = try self.display.getXScreen();

    const outputInfo = try xcb.randr.getOutputInfo(self.display.connection, self.id, 0).reply(self.display.connection);
    const crtcInfo = try xcb.randr.getCrtcInfo(self.display.connection, outputInfo.crtc, 0).reply(self.display.connection);

    const modeInfo = blk: {
        const screenRes = try xcb.randr.getScreenResources(self.display.connection, xscreen.root).reply(self.display.connection);
        var modeIterator = screenRes.modesIterator();
        while (modeIterator.next()) |mode| {
            if (mode.id == crtcInfo.mode.value) break :blk mode;
        }
        return error.ModeNotFound;
    };

    const visual = try self.display.getVisualInfo(xscreen.root_depth, xscreen.root_visual);

    return .{
        .enable = outputInfo.connection == 0,
        .size = .{
            .phys = .{ .value = .{ @floatFromInt(outputInfo.mm_width), @floatFromInt(outputInfo.mm_height) } },
            .res = .{ .value = .{ modeInfo.width, modeInfo.height } },
        },
        .name = outputInfo.name(),
        .colorFormat = Display.getColorFormatFromVisual(visual),
        .scale = self.scale,
    };
}

fn impl_update_info(ctx: *anyopaque, info: phantom.display.Output.Info, fields: []std.meta.FieldEnum(phantom.display.Output.Info)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = info;
    _ = fields;
    return error.NotImplemented;
}

fn impl_deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.display.allocator.destroy(self);
}
