const std = @import("std");
const phantom = @import("phantom");
const Output = @import("output.zig");
const xcb = @import("xcb");
const Self = @This();

base: phantom.display.Surface,
output: *Output,
scene: ?*phantom.scene.Base,
id: xcb.xproto.WINDOW,

pub fn new(output: *Output, id: xcb.xproto.WINDOW) !*Self {
    const self = try output.display.allocator.create(Self);
    errdefer output.display.allocator.destroy(self);

    self.* = .{
        .base = .{
            .ptr = self,
            .vtable = &.{
                .deinit = impl_deinit,
                .destroy = impl_destroy,
                .info = impl_info,
                .updateInfo = impl_update_info,
                .createScene = impl_create_scene,
            },
            .displayKind = output.base.displayKind,
            .kind = .output,
            .type = @typeName(Self),
        },
        .output = output,
        .scene = null,
        .id = id,
    };
    return self;
}

fn impl_deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.output.display.allocator.destroy(self);
}

fn impl_destroy(ctx: *anyopaque) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = self;
}

fn impl_info(ctx: *anyopaque) anyerror!phantom.display.Surface.Info {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = self;
    return error.NotImplemented;
}

fn impl_update_info(ctx: *anyopaque, info: phantom.display.Surface.Info, fields: []std.meta.FieldEnum(phantom.display.Surface.Info)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = info;
    _ = fields;
    return error.NotImplemented;
}

fn impl_create_scene(ctx: *anyopaque, backendType: phantom.scene.BackendType) anyerror!*phantom.scene.Base {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (self.scene) |scene| return scene;

    _ = backendType;
    // TODO: based on backendType or not, you may want to select what kind of scene to initialize.
    return error.NotImplemented;
}
