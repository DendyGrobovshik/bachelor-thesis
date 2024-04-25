const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const print = @import("std").debug.print;
const RndGen = std.rand.DefaultPrng;

const query = @import("query.zig");
const tree = @import("engine/tree.zig");
const utils = @import("utils.zig");

pub var gallocator: Allocator = undefined;
pub var rnd: RndGen = undefined;

// compile and run: `zig build run`
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    gallocator = gpa.allocator();

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!

    // var qwc = try query.Parser().init(std.heap.page_allocator, "A, B -> (A, B) -> A<T> -> (B -> (C, D<T>))");
    // var qwc = try query.Parser().init(std.heap.page_allocator, "A -> B<T> where T < ToString & B, A < X & Y");
    // var qwc = try query.Parser().init(std.heap.page_allocator, "A<T> -> (B -> (C, D<T>))");
    // var qwc = try query.Parser().init(std.heap.page_allocator, "(A, (A, B))");
    // const allocator = std.heap.page_allocator;
    const allocator = gpa.allocator();

    _ = try tree.parseQ(allocator, "A, (R -> F)");

    var t = try tree.buildTreeFromFile("./data/decls2.txt", allocator);

    try t.draw("graph", allocator);

    const ty = try tree.parseQ(allocator, "IntEven -> T where T < Printable & Array<Int>");
    print("parsssed in main: {s}\n", .{ty});
    const res = try t.findDeclarations(ty.ty);

    for (res.items) |decl| {
        print("RESULT: {s}\n", .{decl.name});
    }

    {
        var timer = try std.time.Timer.start();
        try generateDecls();
        print("TIME generateDecls: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    {
        var timer = try std.time.Timer.start();
        t = try tree.buildTreeFromFile("./data/decls3.txt", allocator);
        print("TIME buildTreeFromFile: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    {
        var timer = try std.time.Timer.start();
        try t.draw("graph", allocator);
        print("TIME tree draw: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }
}

fn generateDecls() !void {
    const file = try std.fs.cwd().createFile(
        "./data/decls3.txt",
        .{ .truncate = true },
    );
    defer file.close();

    rnd = RndGen.init(0);
    for (0..100) |_| {
        const typec = try std.fmt.allocPrint(gallocator, "{s}", .{
            try query.TypeC.generate(gallocator),
        });

        try file.writeAll(try std.fmt.allocPrint(gallocator, "{s}: {s}\n", .{
            try utils.randomName(gallocator),
            typec,
        }));
    }
}
