const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const Arena = @import("std").heap.ArenaAllocator;
const SegmentedList = @import("std").SegmentedList;

const LOG = @import("config").logt;

const EngineError = @import("error.zig").EngineError;
const query = @import("../query.zig");
const TypeC = @import("../query.zig").TypeC;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const utils = @import("utils.zig");
const Following = @import("following.zig").Following;
const constants = @import("constants.zig");
const Cache = @import("cache.zig").Cache;
const cache = @import("cache.zig");

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

pub const Variance = enum {
    invariant,
    covariant,
    contravariant,
    bivariant,

    pub fn format(
        this: Variance,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try switch (this) {
            .invariant => writer.print("invariant", .{}),
            .covariant => writer.print("covariant", .{}),
            .contravariant => writer.print("contravariant", .{}),
            .bivariant => writer.print("bivariant", .{}),
        };
    }

    fn inverse(self: Variance) Variance {
        return switch (self) {
            .invariant => Variance.invariant,
            .covariant => Variance.contravariant,
            .contravariant => Variance.covariant,
            .bivariant => Variance.bivariant,
        };
    }

    // commutative, associative
    pub fn x(self: Variance, other: Variance) Variance {
        return switch (self) {
            .invariant => Variance.invariant,
            .covariant => other,
            .contravariant => other.inverse(),
            .bivariant => switch (other) {
                .invariant => Variance.invariant,
                else => Variance.bivariant,
            },
        };
    }
};

pub const VarianceConfig = struct {
    functionIn: Variance,
    functionOut: Variance,
    nominativeGeneric: Variance,
    tupleVariance: Variance,
};

pub const defaultVariances = .{
    .functionIn = Variance.contravariant,
    .functionOut = Variance.covariant,
    .nominativeGeneric = Variance.invariant,
    .tupleVariance = Variance.covariant,
};

// TODO: allocator optimization(everywhere)
pub const Tree = struct {
    head: *Node,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Tree {
        cache.cache = try Cache.init(allocator);
        const head = try Node.init(allocator, &constants.PREROOT);

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
        //try file.writeAll("rankdir=LR;");
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

        const ty = utils.orderTypeParameters(decl_.ty, self.allocator);
        const leaf = try self.sweetLeaf(ty, self.allocator);

        const following = try leaf.getFollowing(try utils.getBacklink(ty), Following.Kind.arrow, self.allocator);

        // // TODO: this is a hack because some kind of miscompilation reuse same memory
        // // and all the declaration names are indistinguishable(last name are applied to all)
        const newName = try std.fmt.allocPrint(self.allocator, "{s}", .{decl_.name});
        const decl = try Declaration.init(self.allocator, newName, ty);
        try following.to.endings.append(decl);

        // try leaf.endings.append(.{ .type = decl.type, .name = newName });

        if (LOG) {
            std.debug.print("=====DECLARATION ADDED\n", .{});
        }
    }

    pub fn findDeclarations(self: *Tree, typec_: *TypeC) EngineError!std.ArrayList(*Declaration) {
        return self.findDeclarationsWithVariants(typec_, Variance.invariant);
    }

    pub fn findDeclarationsWithVariants(self: *Tree, typec_: *TypeC, variance: Variance) EngineError!std.ArrayList(*Declaration) {
        if (LOG) {
            std.debug.print("Searcing declaration...\n", .{});
        }

        // // NOTE: for some reasom self.allocator is not enough and `recursiveTypeProcessor` fails
        // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        // const allocator = gpa.allocator();
        var result = std.ArrayList(*Declaration).init(self.allocator);

        const typec = utils.orderTypeParameters(typec_, self.allocator);
        const leafs = try self.head.searchWithVariance(typec, variance, self.allocator);
        for (leafs.items) |leaf| {
            const following = try leaf.getFollowing(try utils.getBacklink(typec), Following.Kind.arrow, self.allocator);

            try result.appendSlice(following.to.endings.items);
        }

        if (utils.canBeDecurried(typec)) { // TODO: add check "if here is available vacancies"
            const decurried = try utils.decurryType(self.allocator, typec);
            const ordered = utils.orderTypeParameters(decurried, self.allocator);

            const leafs2 = try self.head.searchWithVariance(ordered, variance, self.allocator);
            for (leafs2.items) |leaf2| {
                const following2 = try leaf2.getFollowing(try utils.getBacklink(ordered), Following.Kind.arrow, self.allocator);

                try result.appendSlice(following2.to.endings.items);
            }
        }

        return result;
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
