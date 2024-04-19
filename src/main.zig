const std = @import("std");
const print = @import("std").debug.print;

const query = @import("query.zig");
const tree = @import("engine/tree.zig");

// compile and run: `zig build run`
pub fn main() !void {
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
}
