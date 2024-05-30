const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const print = @import("std").debug.print;
const RndGen = std.rand.DefaultPrng;

const utils = @import("utils.zig");
const queryParser = @import("query_parser.zig");

const Client = @import("driver/client.zig").Client;
const KotlinClient = @import("driver/kotlin_client.zig").KotlinClient;
const Tree = @import("engine/tree.zig").Tree;

// TODO: it's currently hack, should be removed
pub var rnd: RndGen = undefined;

// compile and run: `zig build run`
pub fn main() !void {
    rnd = RndGen.init(0);

    // try demoParsing();
    // try demoTree();
    try demoServer();
    // try demoSubtyping();
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

    const handle = try std.Thread.spawn(.{}, Client.sleepAndRun, .{
        allocator,
    });

    const tree = try Tree.runAsServer(allocator);

    handle.join();

    print("Memory used: {d:.2} KB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000.0});
    print("Memory used: {d:.2} MB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000000.0});

    try tree.draw("graph", allocator);
    try tree.drawCache("cache", allocator);
    tree.cache.statistic.print();
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
        var declIt = (try tree.findDeclarations(query.ty)).keyIterator(); // do exact search!

        while (declIt.next()) |decl| {
            print("Found declaration: {s}\n", .{decl.*.name});
        }
    }

    { // Composing exression String ~> Bool
        print("Composing expressions for: 'String ~> Bool'\n", .{});
        const in = try queryParser.parseQuery(allocator, "String");
        const out = try queryParser.parseQuery(allocator, "Bool");

        var timer = try std.time.Timer.start();
        const res = try tree.composeExpression(in.ty, out.ty);
        print("TIME composeExpression: {}\n", .{std.fmt.fmtDuration(timer.read())});

        for (res.items) |expr| {
            print("Candidate expression: {any}\n", .{expr});
        }
    }
}

fn startServer() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const tree = try Tree.runAsServer(allocator);

    print("Memory used: {d:.2} KB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000.0});
    print("Memory used: {d:.2} MB\n", .{@as(f64, @floatFromInt(arena.queryCapacity())) / 1000000.0});

    try tree.draw("graph", allocator);
    tree.cache.statistic.print();
}

fn demoSubtyping() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var tree: *Tree = undefined;
    { // Building tree from file
        tree = try Tree.buildTreeFromFile("./data/decls5.txt", allocator);
    }

    // visualizing tree in graph.png
    try tree.draw("graph", allocator);
}
