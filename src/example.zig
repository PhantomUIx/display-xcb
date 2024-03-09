const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const phantom = @import("phantom");
const vizops = @import("vizops");

const alloc = if (builtin.link_libc) std.heap.c_allocator else std.heap.page_allocator;

pub fn main() !void {
    var display = try phantom.display.Backend(.xcb).Display.init(alloc, .client);
    defer display.deinit();

    const outputs = try @constCast(&display.display()).outputs();
    defer {
        for (outputs.items) |output| output.deinit();
        outputs.deinit();
    }

    const output = blk: {
        for (outputs.items) |value| {
            if ((try value.info()).enable) break :blk value;
        }
        @panic("Could not find an output");
    };

    const surface = output.createSurface(.view, .{
        .size = .{
            .value = .{ 1024, 768 },
        },
    }) catch |e| @panic(
        @errorName(e),
    );

    defer {
        surface.destroy() catch {};
        surface.deinit();
    }

    const scene = try surface.createScene(.fb);
    const flex = try scene.createNode(.NodeFlex, .{
        .direction = .horizontal,
        .children = &.{
            try scene.createNode(.NodeRect, .{
                .color = .{
                    .uint8 = .{
                        .sRGB = .{
                            .value = .{ 255, 255, 255, 255 },
                        },
                    },
                },
                .size = vizops.vector.Float32Vector2.init([_]f32{ 100.0, 100.0 }),
            }),
        },
    });
    defer flex.deinit();

    while (true) {
        const seq = scene.seq;
        _ = try scene.frame(flex);
        if (seq != scene.seq) std.debug.print("Frame #{}\n", .{scene.seq});
    }
}
