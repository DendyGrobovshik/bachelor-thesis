const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Arena = @import("std").heap.ArenaAllocator;
const SegmentedList = @import("std").SegmentedList;

const LOG = @import("config").logt;

const EngineError = @import("error.zig").EngineError;
const query = @import("../query.zig");
const TypeC = @import("../query.zig").TypeC;
const Node = @import("node.zig").Node;
const TypeNode = @import("typeNode.zig").TypeNode;
const utils = @import("utils.zig");
const typeNode = @import("typeNode.zig");

pub const Declaration = struct {
    name: []const u8,
    ty: *query.TypeC,

    pub fn init(allocator: Allocator, name: []const u8, ty: *TypeC) !*Declaration {
        const self = try allocator.create(Declaration);

        self.* = .{
            .name = name,
            .ty = ty,
        };

        return self;
    }
};

// pub const EngineError = error{
//     CanNotInsert,
//     CanNotFindNode,
//     NotYetSupported,
// } || std.mem.Allocator.Error || Node.NodeError;

// TODO: allocator optimization(everywhere)
pub const Tree = struct {
    head: *Node,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Tree {
        const head = try Node.init(allocator, &typeNode.PREROOT);

        return .{
            .head = head,
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *Tree) void {
        // TODO:
    }

    // uses dot to visualize builded tree
    pub fn draw(self: *const Tree, path: []const u8, allocator: Allocator) !void {
        const file = try std.fs.cwd().createFile(
            path,
            .{ .truncate = true },
        );
        defer file.close();

        try file.writeAll("digraph g {\n");
        try file.writeAll("compound = true;\n");
        try self.head.draw(file, allocator);

        try file.writeAll("}\n");

        const pngPath = try std.fmt.allocPrint(allocator, "{s}.png", .{path});

        // TODO: handle proper error handling
        _ = try std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = &.{
                "dot", "-T", "png", path, "-o", pngPath,
            },
        });

        if (LOG) {
            std.debug.print("TREE DRAWN...\n", .{});
        }
    }

    pub fn sweetLeaf(self: *Tree, typec: *TypeC, allocator: Allocator) EngineError!*TypeNode {
        return try self.head.search(typec, allocator);
    }

    // no comma + generic transformed to func
    pub fn addDeclaration(self: *Tree, decl_: *Declaration) EngineError!void {
        // const decl = try utils.preprocessDeclaration(self.allocator, decl_);

        if (LOG) {
            std.debug.print("======ADDING DECLARATION... {s}\n", .{decl_.name});
        }

        const leaf = try self.sweetLeaf(decl_.ty, self.allocator);

        const following = try leaf.getFollowing(try utils.getBacklink(decl_.ty), self.allocator);

        // // TODO: this is a hack because some kind of miscompilation reuse same memory
        // // and all the declaration names are indistinguishable(last name are applied to all)
        const newName = try std.fmt.allocPrint(self.allocator, "{s}", .{decl_.name});
        const decl = try Declaration.init(self.allocator, newName, decl_.ty);
        try following.to.endings.append(decl);

        // try leaf.endings.append(.{ .type = decl.type, .name = newName });

        if (LOG) {
            std.debug.print("=====DECLARATION ADDED\n", .{});
        }
    }

    pub fn findDeclarations(self: *Tree, typec: *TypeC) EngineError!std.ArrayList(*Declaration) {
        if (LOG) {
            std.debug.print("Searcing declaration...\n", .{});
        }

        // // NOTE: for some reasom self.allocator is not enough and `recursiveTypeProcessor` fails
        // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        // const allocator = gpa.allocator();

        const leaf = try self.head.search(typec, self.allocator);
        const following = try leaf.getFollowing(try utils.getBacklink(typec), self.allocator);

        return following.to.endings;
    }

    pub fn extractAllDecls(self: *Tree, allocator: Allocator) !std.ArrayList(*Declaration) {
        const allDecls = try self.head.extractAllDecls(allocator);

        var unique = std.AutoHashMap(*Declaration, void).init(allocator);
        for (allDecls.items) |decl| {
            try unique.put(decl, {});
        }

        var result = std.ArrayList(*Declaration).init(allocator);
        var it = unique.keyIterator();
        while (it.next()) |decl| {
            try result.append(decl.*);
        }

        return result;
    }
};

// testing function
pub fn parseQ(allocator: Allocator, str: []const u8) !query.Query {
    var parser = try query.Parser().init(allocator, str);
    const q = parser.parse() catch |err| {
        parser.printError(err);
        return err;
    };

    if (LOG) {
        std.debug.print("PARSED Q: {}\n", .{q});
    }

    return q;
}

// testing functions
pub fn buildTreeFromFile(path: []const u8, allocator: Allocator) !Tree {
    if (LOG) {
        std.debug.print("BUILDING TREE FROM FILE...\n", .{});
    }

    var tree = try Tree.init(allocator);

    const file = try std.fs.cwd().openFile(
        path,
        .{},
    );
    defer file.close();

    var bufReader = std.io.bufferedReader(file.reader());
    var inStream = bufReader.reader();

    var buf: [1024]u8 = undefined;
    while (try inStream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (!std.mem.containsAtLeast(u8, line, 1, ":")) {
            continue;
        }

        var it = std.mem.split(u8, line, ":");
        const name = std.mem.trim(u8, it.next().?, " ");

        const q = try parseQ(allocator, it.next().?);

        // const decl = Declaration{ .name = name, .ty = q.type };
        const decl = try allocator.create(Declaration);
        decl.* = .{
            .name = name,
            .ty = q.ty,
        };

        try tree.addDeclaration(decl);
    }

    return tree;
}

// test "tree with one function" {
//     var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
//     defer arena.deinit();

//     // create declaration
//     var parser = try query.Parser().init(arena.allocator(), "A -> B -> C");
//     defer parser.deinit();
//     const ty: *Type = try parser.parseType();
//     const decl = Declaration{ .name = "foo", .type = ty.* };

//     // create tree
//     var tree = try Tree.init(arena.allocator());
//     defer tree.deinit();

//     try tree.addDeclaration(decl);

//     const found = (try tree.findDeclarations(ty.*)).getLast();

//     try std.testing.expectEqualDeep(decl, found);
// }

// test "simple tree" {
//     // checks that it is being built without problems
//     _ = try buildTreeFromFile("test_data/simple_tree.txt");
// }

// test "tree with HOF" {
//     var tree = try buildTreeFromFile("test_data/tree_hof.txt");

//     const foo = try parseQ(std.testing.allocator, "A -> B -> C");
//     const fooDecl = (try tree.findDeclarations(foo.type.*)).getLast();

//     try std.testing.expectEqualStrings("foo", fooDecl.name);

//     const hof = try parseQ(std.testing.allocator, "(A -> B) -> C");
//     const hofDecl = (try tree.findDeclarations(hof.type.*)).getLast();

//     try std.testing.expectEqualStrings("hof", hofDecl.name);

//     try std.testing.expect(!std.meta.eql(fooDecl, hofDecl));
// }
