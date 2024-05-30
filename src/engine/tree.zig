const std = @import("std");
const net = std.net;
const Allocator = @import("std").mem.Allocator;
const Arena = @import("std").heap.ArenaAllocator;
const SegmentedList = @import("std").SegmentedList;

const queryParser = @import("../query_parser.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");
const defaultVariances = @import("variance.zig").defaultVariances;

const AutoHashSet = utils.AutoHashSet;
const EngineError = @import("error.zig").EngineError;
const TypeC = @import("../query_parser.zig").TypeC;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const Following = @import("following.zig").Following;
const Cache = @import("cache.zig").Cache;
const Variance = @import("variance.zig").Variance;
const Declaration = @import("entities.zig").Declaration;
const Expression = @import("entities.zig").Expression;
const Server = @import("../driver/server.zig").Server;
const Mirror = @import("entities.zig").Mirror;

pub var current: *Tree = undefined;

// TODO: allocator optimization(everywhere)
pub const Tree = struct {
    head: *Node,
    allocator: Allocator,
    server: ?*Server = null, // used as oracle
    cache: *Cache,

    pub fn init(allocator: Allocator) !*Tree {
        const this = try allocator.create(Tree);

        const head = try Node.init(allocator, &constants.PREROOT);

        this.* = .{
            .head = head,
            .allocator = allocator,
            .cache = try Cache.init(allocator),
        };
        current = this;
        return this;
    }

    pub fn runAsServer(allocator: Allocator) !*Tree {
        var tree = try Tree.init(allocator);

        var server = try Server.initAndBind(allocator);
        tree.server = server;

        try server.awaitAndGreetClient();
        try server.buildTree(tree);
        std.debug.print("Tree: builded by clients declarations", .{});
        tree.cache.statistic.print();
        try server.answerQuestions(tree);

        return tree;
    }

    pub fn buildTreeFromFile(path: []const u8, allocator: Allocator) !*Tree {
        // std.debug.print("BUILDING TREE FROM FILE...\n", .{});

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

            const decl = try Declaration.init(
                allocator,
                try Allocator.dupe(allocator, u8, name),
                q.ty,
                declId,
            );

            try t.addDeclaration(decl);
        }

        return t;
    }

    pub fn deinit(_: *Tree) void {
        // TODO:
    }

    pub fn draw(self: *const Tree, path: []const u8, allocator: Allocator) !void {
        try doDraw(self.head, path, allocator);
    }

    pub fn drawCache(self: *const Tree, path: []const u8, allocator: Allocator) !void {
        try doDraw(self.cache.head, path, allocator);
    }

    // uses dot to visualize builded tree
    pub fn doDraw(node: *Node, path: []const u8, allocator: Allocator) !void {
        // std.debug.print("Start drawing tree\n", .{});
        const file = try std.fs.cwd().createFile(
            path,
            .{ .truncate = true },
        );
        defer file.close();

        try file.writeAll("digraph g {\n");
        try file.writeAll("compound = true;\n");
        // try file.writeAll("rankdir=LR;");
        try node.draw(file, allocator);

        try file.writeAll("}\n");

        const pngPath = try std.fmt.allocPrint(allocator, "{s}.png", .{path});

        const runResult = try std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = &.{
                "dot", "-T", "png", path, "-o", pngPath,
            },
        });

        // std.debug.print("{any}\n", .{runResult.term});
        switch (runResult.term) {
            .Exited => if (runResult.term.Exited != 0) {
                std.debug.print("Executing 'dot' return non zero code={}, path={s} stderr:\n> {s}\n", .{
                    runResult.term.Exited,
                    path,
                    runResult.stderr,
                });
                return EngineError.ErrorWhileExecutingDot;
            },
            else => return EngineError.ErrorWhileExecutingDot,
        }

        // std.debug.print("TREE DRAWN...\n", .{});
    }

    pub fn sweetLeaf(self: *Tree, typec: *TypeC, allocator: Allocator) EngineError!*TypeNode {
        return try self.head.search(typec, allocator);
    }

    // no comma + generic transformed to func
    pub fn addDeclaration(self: *Tree, decl: *Declaration) EngineError!void {
        // std.debug.print("======ADDING DECLARATION... '{s}' with type '{s}' and index={}\n", .{ decl_.name, decl_.ty, decl_.id });

        const ty = utils.orderTypeParameters(decl.ty, self.allocator);
        const leaf = try self.sweetLeaf(ty, self.allocator);

        const following = try leaf.getFollowing(try utils.getBacklink(ty), Following.Kind.arrow, self.allocator);

        try following.to.endings.append(decl);

        // std.debug.print("=====DECLARATION ADDED\n", .{});
    }

    /// exact search
    pub fn findDeclarations(self: *Tree, typec_: *TypeC) EngineError!AutoHashSet(*Declaration) {
        return self.findDeclarationsWithVariants(typec_, Variance.invariant);
    }

    // TODO: prove that they are unique
    pub fn findDeclarationsWithVariants(self: *Tree, typec_: *TypeC, variance: Variance) EngineError!AutoHashSet(*Declaration) {
        const typec = utils.orderTypeParameters(typec_, self.allocator);

        var leafs = AutoHashSet(*TypeNode).init(self.allocator);
        try self.head.searchWithVariance(typec, variance, &leafs, self.allocator);

        var result = try self.getDeclsOfLeafs(typec, &leafs);

        if (utils.canBeDecurried(typec)) { // TODO: add check "if here is available vacancies"
            const decurried = try utils.decurryType(self.allocator, typec);
            const ordered = utils.orderTypeParameters(decurried, self.allocator);

            var leafs2 = AutoHashSet(*TypeNode).init(self.allocator);
            try self.head.searchWithVariance(ordered, variance, &leafs2, self.allocator);
            var leafs2It = leafs2.keyIterator();
            while (leafs2It.next()) |leaf2| {
                const following2 = try leaf2.*.getFollowing(try utils.getBacklink(ordered), Following.Kind.arrow, self.allocator);

                for (following2.to.endings.items) |decl| {
                    try result.put(decl, {});
                }
            }
        }

        return result;
    }

    fn getDeclsOfLeafs(self: *Tree, typec: *TypeC, leafs: *AutoHashSet(*TypeNode)) EngineError!AutoHashSet(*Declaration) {
        var result = AutoHashSet(*Declaration).init(self.allocator);

        var leafsIt = leafs.keyIterator();
        while (leafsIt.next()) |leaf| {
            const declsOfLeaf = try self.getDeclsOfLeaf(leaf.*, typec);

            for (declsOfLeaf.items) |decl| {
                try result.put(decl, {});
            }
        }

        return result;
    }

    fn getDeclsOfLeaf(self: *Tree, leaf: *TypeNode, typec: *TypeC) EngineError!std.ArrayList(*Declaration) {
        // TODO: check `try utils.getBacklink(typec)`
        // It can be wrong due to searching with variance
        const following = try leaf.getFollowing(try utils.getBacklink(typec), Following.Kind.arrow, self.allocator);

        return following.to.endings;
    }

    // A little bit about variances:
    // f: In -> X'
    //    -     +      Default function variances
    //
    // g: X -> Out
    //    -    +      Default function variances
    //
    // X' < X
    // g ∘ f  = g(f(In))
    //
    // in: In
    // f: In -> X'
    // x: X' = f(in)
    // g: X -> Out
    // out: Out = g(x)
    pub fn composeExpression(self: *Tree, in: *TypeC, out: *TypeC) EngineError!std.ArrayList(Expression) {
        const inVariance = Variance.contravariant.x(defaultVariances.functionIn);

        var leafsX_starts = AutoHashSet(*TypeNode).init(self.allocator);
        try self.head.searchWithVariance(in, inVariance, &leafsX_starts, self.allocator);

        var x_mirrors = AutoHashSet(Mirror).init(self.allocator);

        var leafsX_startsIt = leafsX_starts.keyIterator();
        while (leafsX_startsIt.next()) |x_start| {
            const x_startFollowingNode = try x_start.*.getFollowing(try utils.getBacklink(in), Following.Kind.arrow, self.allocator); // TOOD: check twice
            // std.debug.print("Mirror Walk: '{s}' and '{s}'\n", .{
            //     try x_startFollowingNode.to.labelName(self.allocator),
            //     try self.head.labelName(self.allocator),
            // });
            try x_startFollowingNode.to.mirrorWalk(self.head, &x_mirrors, self.allocator);
        }

        var result = std.ArrayList(Expression).init(self.allocator);
        const outVariance = Variance.covariant.x(defaultVariances.functionOut);

        var x_mirrorsIt = x_mirrors.keyIterator();
        while (x_mirrorsIt.next()) |mirror| {
            // std.debug.print("mirrors: '{s}' with {} decls, '{s}'\n", .{
            //     try mirror.it.labelName(self.allocator),
            //     mirror.it.endings.items.len,
            //     try mirror.reflection.labelName(self.allocator),
            // });

            var leafsOut = AutoHashSet(*TypeNode).init(self.allocator);
            try mirror.*.reflection.searchWithVariance(out, outVariance, &leafsOut, self.allocator);

            const outerDecls = try self.getDeclsOfLeafs(out, &leafsOut);

            const innerDecls = mirror.*.it.endings;

            var outerDeclsIt = outerDecls.keyIterator();
            while (outerDeclsIt.next()) |outer| {
                for (innerDecls.items) |inner| {
                    try result.append(Expression{ .inner = inner, .outer = outer.* });
                }
            }
        }

        return result;
    }

    pub fn extractAllDecls(self: *Tree, allocator: Allocator) Allocator.Error!AutoHashSet(*Declaration) {
        var decls = AutoHashSet(*Declaration).init(allocator);
        try self.head.extractAllDecls(&decls);

        return decls;
    }
};

// TODO: add tests
