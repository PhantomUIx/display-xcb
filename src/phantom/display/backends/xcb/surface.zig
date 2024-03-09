const std = @import("std");
const phantom = @import("phantom");
const Display = @import("display.zig");
const Output = @import("output.zig");
const Fb = @import("../../../painting/fb/xcb-pixmap.zig");
const xcb = @import("xcb");
const Self = @This();

base: phantom.display.Surface,
output: *Output,
scene: ?*phantom.scene.Base,
id: xcb.xproto.WINDOW,
shmseg: ?xcb.shm.SEG,
fd: ?std.os.fd_t,
shmid: ?usize,
shmaddr: ?usize,
fb: ?*phantom.painting.fb.Base,

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
        .shmseg = null,
        .fd = null,
        .shmid = null,
        .shmaddr = null,
        .fb = null,
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
    const attrs = try xcb.xproto.getWindowAttributes(self.output.display.connection, self.id).reply(self.output.display.connection);
    const geom = try xcb.xproto.getGeometry(self.output.display.connection, .{ .window = self.id }).reply(self.output.display.connection);

    const xscreen = try self.output.display.getXScreen();
    const visual = try self.output.display.getVisualInfo(xscreen.root_depth, attrs.visual);

    return .{
        .title = try self.output.display.getProperty(self.id, "_UTF8_STRING", "_NET_WM_NAME") orelse try self.output.display.getProperty(self.id, "STRING", "WM_NAME"),
        .colorFormat = Display.getColorFormatFromVisual(visual),
        .size = .{ .value = .{ geom.width, geom.height } },
        .states = if (attrs.map_state == 2) &.{.mapped} else &.{},
    };
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

    const info = try self.base.info();
    const outputInfo = try self.output.base.info();
    const xscreen = try self.output.display.getXScreen();

    self.shmseg = .{ .value = try self.output.display.connection.generateId() };
    self.shmid = std.os.linux.syscall3(.shmget, 0, @reduce(.Mul, info.size.value) * @divExact(info.colorFormat.?.width(), 8), 0x200 | 0o0777);
    switch (std.os.linux.getErrno(self.shmid.?)) {
        .SUCCESS => {},
        else => |e| return std.os.unexpectedErrno(e),
    }

    self.shmaddr = std.os.linux.syscall3(.shmat, @bitCast(self.shmid.?), 0, 0);
    switch (std.os.linux.getErrno(self.shmaddr.?)) {
        .SUCCESS => {},
        else => |e| return std.os.unexpectedErrno(e),
    }

    if (self.output.display.connection.requestCheck(xcb.shm.attachFd(self.output.display.connection, self.shmseg.?, @intCast(self.shmid.?), 0))) |err| {
        _ = err;
        return error.GenericError;
    }

    switch (std.os.linux.getErrno(std.os.linux.syscall3(.shmctl, @bitCast(self.shmid.?), 0, 0))) {
        .SUCCESS => {},
        else => |e| return std.os.unexpectedErrno(e),
    }

    self.fb = try Fb.create(self.output.display, try phantom.painting.fb.MemoryFrameBuffer.create(self.output.display.allocator, .{
        .res = info.size,
        .colorspace = .sRGB,
        .colorFormat = info.colorFormat orelse outputInfo.colorFormat,
    }, @ptrFromInt(self.shmaddr.?)), .{ .window = self.id }, xscreen.root_depth, self.shmseg.?);

    self.scene = try phantom.scene.createBackend(backendType, .{
        .allocator = self.output.display.allocator,
        .frame_info = phantom.scene.Node.FrameInfo.init(.{
            .res = info.size,
            .scale = outputInfo.scale,
            .physicalSize = outputInfo.size.phys,
            .colorFormat = info.colorFormat orelse outputInfo.colorFormat,
        }),
        .target = .{ .fb = self.fb.? },
    });
    return self.scene.?;
}
