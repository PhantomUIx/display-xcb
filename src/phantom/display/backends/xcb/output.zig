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

    const xscreen = try self.display.getXScreen();
    const tree = try xcb.xproto.queryTree(self.display.connection, xscreen.root).reply(self.display.connection);
    for (tree.children()) |child| {
        const surf = try Surface.new(self, child);
        errdefer surf.base.deinit();
        try surfaces.append(&surf.base);
    }
    return surfaces;
}

fn impl_create_surface(ctx: *anyopaque, kind: phantom.display.Surface.Kind, info: phantom.display.Surface.Info) anyerror!*phantom.display.Surface {
    const self: *Self = @ptrCast(@alignCast(ctx));

    _ = self;
    _ = kind;
    _ = info;
    return error.NotImplemented;
}

fn impl_info(ctx: *anyopaque) anyerror!phantom.display.Output.Info {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const outputInfo = try xcb.randr.getOutputInfo(self.display.connection, self.id, 0).reply(self.display.connection);
    const crtcInfo = try xcb.randr.getCrtcInfo(self.display.connection, outputInfo.crtc, 0).reply(self.display.connection);

    return .{
        .enable = true,
        .size = .{
            .phys = .{ .value = .{ @floatFromInt(outputInfo.mm_width), @floatFromInt(outputInfo.mm_height) } },
            .res = .{ .value = .{ crtcInfo.width, crtcInfo.height } },
        },
        .name = outputInfo.name(),
        .colorFormat = .{ .rgba = @splat(8) },
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
