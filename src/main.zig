const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const print = @import("std").debug.print;
const RndGen = std.rand.DefaultPrng;

const utils = @import("utils.zig");
const queryParser = @import("query_parser.zig");
const randomTree = @import("random_tree.zig").randomTree;

const Client = @import("driver/client.zig").Client;
const KotlinClient = @import("driver/kotlin_client.zig").KotlinClient;
const Tree = @import("engine/tree.zig").Tree;
const Variance = @import("engine/variance.zig").Variance;
const Declaration = @import("engine/entities.zig").Declaration;

// compile and run: `zig build run`
pub fn main() !void {
    // try demoParsing();
    // try demoTree();
    try demoServer();
    // try demoSubtyping();

    // try randomTree(100, 2);
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
    try tree.drawCache("cache", allocator);

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
        const res = try tree.composeExpressions(in.ty, out.ty);
        print("TIME composeExpressions: {}\n", .{std.fmt.fmtDuration(timer.read())});

        var it = res.keyIterator();
        while (it.next()) |expr| {
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
