const std = @import("std");
const Allocator = std.mem.Allocator;
const Display = @import("../../display/backends/xcb/display.zig");
const vizops = @import("vizops");
const phantom = @import("phantom");
const xcb = @import("xcb");
const XcbPixmapFrameBuffer = @This();

display: *Display,
drawable: xcb.xproto.DRAWABLE,
depth: u8,
parent: *phantom.painting.fb.Base,
base: phantom.painting.fb.Base,
id: xcb.xproto.PIXMAP,
gc: xcb.xproto.GCONTEXT,
seg: xcb.shm.SEG,

pub fn create(
    display: *Display,
    parent: *phantom.painting.fb.Base,
    drawable: xcb.xproto.DRAWABLE,
    depth: u8,
    seg: xcb.shm.SEG,
) !*phantom.painting.fb.Base {
    const alloc = parent.allocator;
    const self = try alloc.create(XcbPixmapFrameBuffer);
    errdefer alloc.destroy(self);

    const connection = display.connection;

    self.* = .{
        .display = display,
        .parent = parent,
        .drawable = drawable,
        .depth = depth,
        .base = .{
            .allocator = alloc,
            .ptr = self,
            .vtable = &.{
                .addr = impl_addr,
                .info = impl_info,
                .dupe = impl_dupe,
                .commit = impl_commit,
                .deinit = impl_deinit,
                .blt = null,
            },
        },
        .id = .{ .value = try connection.generateId() },
        .gc = .{ .value = try connection.generateId() },
        .seg = seg,
    };

    const info = parent.info();
    const xscreen = try display.getXScreen();

    if (connection.requestCheck(xcb.xproto.createGC(connection, self.gc, drawable, 1 << 2 | 1 << 16, &[_:0]u32{ xscreen.black_pixel, 0 }))) |_| {
        return error.GenericError;
    }

    if (connection.requestCheck(xcb.shm.createPixmap(connection, self.id, drawable, @intCast(info.res.value[0]), @intCast(info.res.value[1]), depth, seg, 0))) |_| {
        return error.GenericError;
    }
    return &self.base;
}

fn impl_addr(ctx: *anyopaque) anyerror!*anyopaque {
    const self: *XcbPixmapFrameBuffer = @ptrCast(@alignCast(ctx));
    return try self.parent.addr();
}

fn impl_info(ctx: *anyopaque) phantom.painting.fb.Base.Info {
    const self: *XcbPixmapFrameBuffer = @ptrCast(@alignCast(ctx));
    return self.parent.info();
}

fn impl_dupe(ctx: *anyopaque) anyerror!*phantom.painting.fb.Base {
    const self: *XcbPixmapFrameBuffer = @ptrCast(@alignCast(ctx));
    return try create(self.display, try self.parent.dupe(), self.drawable, self.depth, self.seg);
}

fn impl_commit(ctx: *anyopaque) anyerror!void {
    const self: *XcbPixmapFrameBuffer = @ptrCast(@alignCast(ctx));
    try self.parent.commit();

    const info = self.parent.info();
    const connection = self.display.connection;
    if (connection.requestCheck(xcb.xproto.copyArea(connection, .{ .pixmap = self.id }, self.drawable, self.gc, 0, 0, 0, 0, @intCast(info.res.value[0]), @intCast(info.res.value[1])))) |_| {
        return error.GenericError;
    }

    try connection.flush();
}

fn impl_deinit(ctx: *anyopaque) void {
    const self: *XcbPixmapFrameBuffer = @ptrCast(@alignCast(ctx));
    self.parent.deinit();
}
