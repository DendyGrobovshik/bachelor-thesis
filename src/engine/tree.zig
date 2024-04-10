const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Arena = @import("std").heap.ArenaAllocator;
const SegmentedList = @import("std").SegmentedList;

const query = @import("../query.zig");
const Type = @import("../query.zig").Type;
const Node = @import("node.zig").Node;
const TypeNode = @import("typeNode.zig").TypeNode;

pub const Declaration = struct {
    name: []const u8,
    type: query.Type,
};

// TODO: allocator optimization
pub const Tree = struct {
    pub const TreeOperationError = error{
        CanNotInsert,
        CanNotFindNode,
        NotYetSupported,
    } || std.mem.Allocator.Error;

    head: Node,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Tree {
        const head = try Node.init(allocator, "root", 0);

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
        try self.head.draw(file, allocator, "preroot");

        try file.writeAll("}\n");

        const pngPath = try std.fmt.allocPrint(allocator, "{s}.png", .{path});

        // TODO: handle proper error handling
        _ = try std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = &.{
                "dot", "-T", "png", path, "-o", pngPath,
            },
        });
    }

    // no comma + generic transformed to func
    pub fn addDeclaration(self: *Tree, decl_: Declaration) TreeOperationError!void {
        const decl = try self.preprocessDeclaration(decl_);

        std.debug.print("======ADDING DECLARATION...\n", .{});
        const leaf = try self.sweetLeaf(&self.head, decl.type);

        std.debug.print("leaf found\n", .{});

        // TODO: this is a hack because some kind of miscompilation reuse same memory
        // and all the declaration names are indistinguishable(last name are applied to all)
        const newName = try std.fmt.allocPrint(self.allocator, "{s}", .{decl.name});

        try leaf.endings.append(.{ .type = decl.type, .name = newName });

        std.debug.print("=====DECLARATION ADDED\n", .{});
    }

    // TODO: Move out of struct
    fn preprocessDeclaration(self: *Tree, decl: Declaration) TreeOperationError!Declaration {
        const ty: *Type = try self.allocator.create(Type);
        ty.* = decl.type;

        return .{ .type = (try self.recursiveTypeProcessor(ty)).*, .name = decl.name };
    }

    fn recursiveTypeProcessor(self: *Tree, ty: *Type) TreeOperationError!*Type {
        switch (ty.*) {
            .nominative => {
                if (ty.nominative.generic) |genericList| {
                    // TODO: support generic argument with several types
                    const generic = genericList.list.list.items[0];

                    var resTy = try self.allocator.create(Type);
                    resTy.function = .{ .from = generic, .to = ty };
                    return resTy;
                } else {
                    return ty;
                }
            },
            .function => {
                var resTy = try self.allocator.create(Type);
                resTy.function = .{
                    .from = try self.recursiveTypeProcessor(ty.function.from),
                    .to = try self.recursiveTypeProcessor(ty.function.to),
                    .directly = ty.function.directly,
                    .braced = ty.function.braced,
                };
                return resTy;
            },
            .list => return TreeOperationError.NotYetSupported,
        }
    }

    pub fn findDeclarations(self: *Tree, ty: *Type) TreeOperationError!std.ArrayList(Declaration) {
        const leaf = try self.sweetLeaf(&self.head, ty);

        return leaf.endings;
    }

    fn sweetLeaf(self: *Tree, node: *Node, ty: Type) TreeOperationError!*Node {
        std.debug.print("sweetLeaf: {}\n", .{ty});

        switch (ty) {
            .nominative => return try self.leafOfNominative(node, ty),
            .function => return try self.leafOfFunction(node, ty),
            .list => return TreeOperationError.CanNotInsert,
        }
    }

    fn leafOfNominative(self: *Tree, node: *Node, ty: Type) TreeOperationError!*Node {
        std.debug.print("leafOfNominative: {}\n", .{ty});

        const name = ty.nominative.name;

        var typeNode: *TypeNode = undefined;
        if (node.getTypeNode(name)) |typeNode_| {
            typeNode = typeNode_;
        } else {
            try node.insertTypeNode(TypeNode.init(self.allocator, name));

            for (node.types.items) |*typeNode_| {
                if (std.mem.eql(u8, typeNode_.name, name)) {
                    std.debug.print("super size {}\n", .{typeNode_.super.items.len});
                    typeNode_.of = node;
                    typeNode = typeNode_;
                }
            }
        }

        if (typeNode.following) |*following| {
            return following;
        } else {
            const following = try Node.init(self.allocator, name, node.layer + 1);
            typeNode.following = following;

            return &(typeNode.following orelse unreachable);
        }
    }

    fn leafOfFunction(self: *Tree, node: *Node, ty: Type) TreeOperationError!*Node {
        std.debug.print("leafOfFunction: {}\n", .{ty});

        const from = ty.function.from;
        const to = ty.function.to;

        const cont = try switch (from.*) {
            .nominative => try self.leafOfNominative(node, from.*),
            .function => try self.hofLeaf(node, from.*),
            .list => TreeOperationError.CanNotInsert,
        };

        const res = self.sweetLeaf(cont, to.*);

        return res;
    }

    fn hofLeaf(self: *Tree, node: *Node, ty: Type) TreeOperationError!*Node {
        std.debug.print("HOF Leaf: {}\n", .{ty});
        const fakeStart = try self.leafOfNominative(node, .{ .nominative = .{ .name = "functionopening322" } });

        const endNode = try self.sweetLeaf(fakeStart, ty);

        const fakeEnd = try self.leafOfNominative(endNode, .{ .nominative = .{ .name = "functionclosing322" } });

        return fakeEnd;
    }
};

// testing function
pub fn parseQ(str: []const u8) !query.Query {
    var parser = try query.Parser().init(std.heap.page_allocator, str);
    const q = parser.parse() catch |err| {
        parser.printError(err);
        return err;
    };

    std.debug.print("PARSED Q: {}\n", .{q});

    return q;
}

// testing function
pub fn buildTreeFromFile(path: []const u8) !Tree {
    std.debug.print("BUILDING TREE FROM FILE...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
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

        const q = try parseQ(it.next().?);

        const decl = Declaration{ .name = name, .type = q.type.* };

        try tree.addDeclaration(decl);
    }

    return tree;
}

test "tree with one function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // create declaration
    var parser = try query.Parser().init(arena.allocator(), "A -> B -> C");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();
    const decl = Declaration{ .name = "foo", .type = ty.* };

    // create tree
    var tree = try Tree.init(arena.allocator());
    defer tree.deinit();

    try tree.addDeclaration(decl);

    const found = (try tree.findDeclarations(ty.*)).getLast();

    try std.testing.expectEqualDeep(decl, found);
}

test "simple tree" {
    // checks that it is being built without problems
    _ = try buildTreeFromFile("test_data/simple_tree.txt");
}

test "tree with HOF" {
    var tree = try buildTreeFromFile("test_data/tree_hof.txt");

    const foo = try parseQ("A -> B -> C");
    const fooDecl = (try tree.findDeclarations(foo.type.*)).getLast();

    try std.testing.expectEqualStrings("foo", fooDecl.name);

    const hof = try parseQ("(A -> B) -> C");
    const hofDecl = (try tree.findDeclarations(hof.type.*)).getLast();

    try std.testing.expectEqualStrings("hof", hofDecl.name);

    try std.testing.expect(!std.meta.eql(fooDecl, hofDecl));
}

// TODO: alphebetic type solver
