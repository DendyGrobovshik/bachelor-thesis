const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const tree = @import("engine/tree.zig");
const query = @import("query.zig");
const utils = @import("utils.zig");

pub var rnd: RndGen = undefined;rnd

fn generate() !void {
    var t: tree.Tree = undefined;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    {
        var timer = try std.time.Timer.start();
        try generateDecls(allocator);
        std.debug.print("TIME generateDecls: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    {
        var timer = try std.time.Timer.start();
        t = try tree.buildTreeFromFile("./data/decls3.txt", allocator);
        std.debug.print("TIME buildTreeFromFile: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    {
        var timer = try std.time.Timer.start();
        // try t.draw("graph", allocator);
        std.debug.print("TIME tree draw: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }
}

fn generateDecls(allocator: Allocator) !void {
    const file = try std.fs.cwd().createFile(
        "./data/decls3.txt",
        .{ .truncate = true },
    );
    defer file.close();

    for (0..10000) |_| {
        const typec = try std.fmt.allocPrint(allocator, "{s}", .{
            try query.TypeC.generate(allocator),
        });

        try file.writeAll(try std.fmt.allocPrint(allocator, "{s}: {s}\n", .{
            try utils.randomName(allocator),
            typec,
        }));
    }
}
