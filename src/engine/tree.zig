const std = @import("std");
const net = std.net;
const Allocator = @import("std").mem.Allocator;
const Arena = @import("std").heap.ArenaAllocator;
const SegmentedList = @import("std").SegmentedList;

const queryParser = @import("../query_parser.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");

const EngineError = @import("error.zig").EngineError;
const TypeC = @import("../query_parser.zig").TypeC;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const Following = @import("following.zig").Following;
const Cache = @import("cache.zig").Cache;
const Variance = @import("variance.zig").Variance;
const Declaration = @import("entities.zig").Declaration;
const Server = @import("../driver/server.zig").Server;

const LOG = @import("config").logt;

pub var current: *Tree = undefined;

// TODO: allocator optimization(everywhere)
pub const Tree = struct {
    head: *Node,
    allocator: Allocator,
    server: ?*Server = null, // used as oracle
    cache: *Cache,

    pub fn init(allocator: Allocator) !*Tree {
        const this = try allocator.create(Tree);

        const cache_ = try Cache.init(allocator, this);
        const head = try Node.init(allocator, &constants.PREROOT);

        this.* = .{
            .head = head,
            .allocator = allocator,
            .cache = cache_,
        };
        current = this;
        return this;
    }

    pub fn runAsServerAndDraw(allocator: Allocator) !void {
        var tree = try Tree.init(allocator);

        var server = try Server.initAndBind(allocator);
        tree.server = server;

        try server.awaitAndGreetClient();
        try server.buildTree(tree);
        // try server.answerQuestions();

        try tree.draw("graph", allocator);
    }

    pub fn buildTreeFromFile(path: []const u8, allocator: Allocator) !*Tree {
        if (LOG) {
            std.debug.print("BUILDING TREE FROM FILE...\n", .{});
        }

        var t = try Tree.init(allocator);

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

            var declId: usize = 0;
            if (std.mem.containsAtLeast(u8, line, 2, ":")) {
                declId = try std.fmt.parseInt(usize, it.next().?, 10);
            }

            const name = std.mem.trim(u8, it.next().?, " ");

            const q = try queryParser.parseQuery(allocator, it.next().?);

            // const decl = Declaration{ .name = name, .ty = q.type };
            const decl = try allocator.create(Declaration);
            decl.* = .{
                .name = name,
                .ty = q.ty,
                .id = declId,
            };

            try t.addDeclaration(decl);
        }

        return t;
    }

    pub fn deinit(_: *Tree) void {
        // TODO:
    }

    pub fn greater(self: *Tree, parent: *TypeNode, child: *TypeNode) !bool {
        return self.cache.greater(parent, child);
    }

    // uses dot to visualize builded tree
    pub fn draw(self: *const Tree, path: []const u8, allocator: Allocator) !void {
        if (LOG) {
            std.debug.print("Start drawing tree\n", .{});
        }
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
        if (LOG) {
            std.debug.print("======ADDING DECLARATION... '{s}' with type '{s}' and index={}\n", .{ decl_.name, decl_.ty, decl_.id });
        }

        const ty = utils.orderTypeParameters(decl_.ty, self.allocator);
        const leaf = try self.sweetLeaf(ty, self.allocator);

        const following = try leaf.getFollowing(try utils.getBacklink(ty), Following.Kind.arrow, self.allocator);

        // // TODO: this is a hack because some kind of miscompilation reuse same memory
        // // and all the declaration names are indistinguishable(last name are applied to all)
        const newName = try std.fmt.allocPrint(self.allocator, "{s}", .{decl_.name});
        const decl = try Declaration.init(self.allocator, newName, ty);
        try following.to.endings.append(decl);

        if (LOG) {
            std.debug.print("=====DECLARATION ADDED\n", .{});
        }
    }

    /// exact search
    pub fn findDeclarations(self: *Tree, typec_: *TypeC) EngineError!std.ArrayList(*Declaration) {
        return self.findDeclarationsWithVariants(typec_, Variance.invariant);
    }

    pub fn findDeclarationsWithVariants(self: *Tree, typec_: *TypeC, variance: Variance) EngineError!std.ArrayList(*Declaration) {
        if (LOG) {
            std.debug.print("Searcing declaration...\n", .{});
        }

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

    pub fn subtype(self: *Tree, parent: *TypeNode, child: *TypeNode) EngineError!bool {
        if (self.server) |server| {
            return try server.askSubtype(parent, child);
        } else {
            return try Cache.defaultSubtype(parent, child);
        }
    }
};

// TODO: add tests
