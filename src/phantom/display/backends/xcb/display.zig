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

fn getXScreen(self: *Self) !*const xcb.xproto.SCREEN {
    var iter = self.setup.rootsIterator();
    var i: usize = 0;
    while (iter.next()) |screen| : (i += 1) {
        if (i == self.screenId) return screen;
    }
    return error.ScreenNotFound;
}

fn impl_outputs(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Output) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var outputs = std.ArrayList(*phantom.display.Output).init(self.allocator);
    errdefer outputs.deinit();

    const xscreen = try self.getXScreen();
    const monitors = try xcb.randr.getMonitors(@ptrCast(@alignCast(self.connection)), xscreen.root, 0).reply(@ptrCast(@alignCast(self.connection)));
    var monitorsIter = monitors.monitorsIterator();

    while (monitorsIter.next()) |monitor| {
        var outputsIter = monitor.outputsIterator();
        while (outputsIter.next()) |output| {
            std.debug.print("{}\n", .{output});
            try outputs.append(&(try Output.new(self, monitor.name)).base);
        }
    }
    return outputs;
}
