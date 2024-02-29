const std = @import("std");
const Allocator = std.mem.Allocator;
const phantom = @import("phantom");
const Output = @import("output.zig");
const xcb = @import("xcb");
const Self = @This();

allocator: Allocator,
kind: phantom.display.Base.Kind,
connection: *xcb.Connection,
setup: *const xcb.xproto.Setup,

pub fn init(alloc: Allocator, kind: phantom.display.Base.Kind) !Self {
    const conn = try xcb.Connection.connect(null, null);
    return .{
        .allocator = alloc,
        .kind = kind,
        .connection = conn,
        .setup = conn.getSetup(),
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

fn impl_outputs(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Output) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var outputs = std.ArrayList(*phantom.display.Output).init(self.allocator);
    errdefer outputs.deinit();

    // TODO: implement me
    return outputs;
}
