const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const print = @import("std").debug.print;
const RndGen = std.rand.DefaultPrng;

const utils = @import("utils.zig");
const queryParser = @import("query_parser.zig");

const Client = @import("driver/client.zig").Client;
const Tree = @import("engine/tree.zig").Tree;

// TODO: it's currently hack, should be removed
pub var gallocator: Allocator = undefined;
pub var rnd: RndGen = undefined;

// compile and run: `zig build run`
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    gallocator = gpa.allocator();

    rnd = RndGen.init(0);

    // try demoParsing();
    try demoTree();
    // try demoServer();
}

fn demoParsing() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const query = try queryParser.parseQuery(allocator, "Array<String> -> Array<Int>");

    print("Parsed query type: '{s}'\n", .{query.ty});
}

fn demoServer() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const handle = try std.Thread.spawn(.{}, Tree.runAsServerAndDraw, .{
        allocator,
    });

    // awaiting server binding
    std.time.sleep(10 * std.time.ns_per_ms);

    const client = try Client.initAndConnect(allocator);
    try Client.run(client);

    handle.join();

    print("Memory used: {d:.2} KB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000.0});
    print("Memory used: {d:.2} MB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000000.0});
}

fn demoTree() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var tree: *Tree = undefined;
    { // Building tree from file
        var timer = try std.time.Timer.start();
        tree = try Tree.buildTreeFromFile("./data/decls4.txt", allocator);
        print("TIME buildTreeFromFile: {}\n", .{std.fmt.fmtDuration(timer.read())});

        print("Memory used: {d:.2} KB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000.0});
        print("Memory used: {d:.2} MB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000000.0});
    }

    // visualizing tree in graph.png
    try tree.draw("graph", allocator);

    { // Searching declarations by types
        const query = try queryParser.parseQuery(allocator, "String -> Int");
        const res = try tree.findDeclarations(query.ty); // do exact search!

        for (res.items) |decl| {
            print("Found declaration: {s}\n", .{decl.name});
        }
    }

    { // Composing exression String ~> Bool
        print("Composing expressions for: 'String ~> Bool'\n", .{});
        const in = try queryParser.parseQuery(allocator, "String");
        const out = try queryParser.parseQuery(allocator, "Bool");
        const res = try tree.composeExpression(in.ty, out.ty);

        for (res.items) |expr| {
            print("Candidate expression: {any}\n", .{expr});
        }
    }
}
