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

// TODO: threadlocal?
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

    pub fn draw(self: *const Tree, path: []const u8, allocator: Allocator) EngineError!void {
        try doDraw(self.head, path, allocator);
    }

    pub fn drawCache(self: *const Tree, path: []const u8, allocator: Allocator) EngineError!void {
        try doDraw(self.cache.head, path, allocator);
    }

    // uses dot to visualize builded tree
    pub fn doDraw(node: *Node, path: []const u8, allocator_: Allocator) EngineError!void {
        // png or svg
        const FORMAT = "png";
        var arena = std.heap.ArenaAllocator.init(allocator_);
        const allocator = arena.allocator();
        defer arena.deinit();

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

        const pngPath = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ path, FORMAT });

        const runResult = try std.ChildProcess.run(.{
            .allocator = allocator,
            .argv = &.{
                "dot", "-T", FORMAT, path, "-o", pngPath,
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

    /// Do search and insert if needed.
    pub fn sweetLeaf(self: *Tree, typec: *TypeC, allocator: Allocator) EngineError!*TypeNode {
        const config = .{ .variance = Variance.invariant, .insert = true };
        if (try self.head.search(typec, config, allocator)) |leaf| {
            return leaf;
        } else {
            std.debug.panic("Leaf was not found or inserted\n", .{});
        }
    }

    /// Do search, not insert.
    pub fn search(self: *Tree, typec: *TypeC, allocator: Allocator) EngineError!?*TypeNode {
        const config = .{ .variance = Variance.invariant, .insert = false };
        return try self.head.search(typec, config, allocator);
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

    pub fn findDeclarationsWithVariants(self: *Tree, typec_: *TypeC, variance: Variance) EngineError!AutoHashSet(*Declaration) {
        const searchConfig = .{ .variance = variance, .insert = false };
        const typec = utils.orderTypeParameters(typec_, self.allocator);

        var leafs = AutoHashSet(*TypeNode).init(self.allocator);
        try self.head.searchWithVariance(typec, searchConfig, &leafs, self.allocator);

        var result = try self.getDeclsOfLeafs(typec, &leafs);

        if (utils.canBeDecurried(typec)) { // TODO: add check "if here is available vacancies"
            const decurried = try utils.decurryType(self.allocator, typec);
            const ordered = utils.orderTypeParameters(decurried, self.allocator);

            var leafs2 = AutoHashSet(*TypeNode).init(self.allocator);
            try self.head.searchWithVariance(ordered, searchConfig, &leafs2, self.allocator);
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
    pub fn composeExpressions(self: *Tree, in: *TypeC, out: *TypeC) EngineError!AutoHashSet(Expression) {
        const inVariance = Variance.contravariant.x(defaultVariances.functionIn);
        const outVariance = Variance.covariant.x(defaultVariances.functionOut);

        const starts = try nodesBy(in, self.head, inVariance, self.allocator);

        const mirrors = try getMirrors(&starts, self.head, self.allocator);

        return try composeMirrors(&mirrors, out, outVariance, self.allocator);
    }

    /// return all nodes with path equal to `by` type which start in `startsIn` according to `variance`
    fn nodesBy(by: *TypeC, startsIn: *Node, variance: Variance, allocator: Allocator) EngineError!AutoHashSet(*Node) {
        var leafsX_starts = AutoHashSet(*TypeNode).init(allocator);
        const searchConfig = .{ .variance = variance, .insert = false };
        try startsIn.searchWithVariance(by, searchConfig, &leafsX_starts, allocator);

        var result = AutoHashSet(*Node).init(allocator);

        var it = leafsX_starts.keyIterator();
        while (it.next()) |typeNode| {
            const node = (try typeNode.*.getFollowing(try utils.getBacklink(by), Following.Kind.arrow, allocator)).to;
            try result.put(node, {});
        }

        return result;
    }

    /// get mirrors with each of `starts` and `with`
    fn getMirrors(starts: *const AutoHashSet(*Node), with: *Node, allocator: Allocator) EngineError!AutoHashSet(Mirror) {
        var result = AutoHashSet(Mirror).init(allocator);

        var it = starts.keyIterator();
        while (it.next()) |start| {
            // std.debug.print("Mirror Walk: '{s}' and '{s}'\n", .{
            //     try start.*.labelName(allocator),
            //     try with.labelName(allocator),
            // });
            try start.*.mirrorWalk(with, &result, allocator);
        }

        return result;
    }

    /// Compose expression: inner decls is from `it` of mirror,
    ///  and outer decls is from continuation of `reflection` with `ending`
    fn composeMirrors(
        mirrors: *const AutoHashSet(Mirror),
        ending: *TypeC,
        variance: Variance,
        allocator: Allocator,
    ) EngineError!AutoHashSet(Expression) {
        var result = AutoHashSet(Expression).init(allocator);

        var it = mirrors.keyIterator();
        while (it.next()) |mirror| {
            // std.debug.print("mirrors: '{s}' with {} decls, '{s}'\n", .{
            //     try mirror.it.labelName(allocator),
            //     mirror.it.endings.items.len,
            //     try mirror.reflection.labelName(allocator),
            // });

            const nodesOut = try nodesBy(ending, mirror.*.reflection, variance, allocator);
            const outerDecls = try getDeclsOfNodes(&nodesOut, allocator);

            const innerDecls = mirror.*.it.endings;

            var outerDeclsIt = outerDecls.keyIterator();
            while (outerDeclsIt.next()) |outer| {
                for (innerDecls.items) |inner| {
                    try result.put(Expression{ .inner = inner, .outer = outer.* }, {});
                }
            }
        }

        return result;
    }

    fn getDeclsOfNodes(nodes: *const AutoHashSet(*Node), allocator: Allocator) Allocator.Error!AutoHashSet(*Declaration) {
        var result = AutoHashSet(*Declaration).init(allocator);

        var it = nodes.keyIterator();
        while (it.next()) |node| {
            for (node.*.endings.items) |decl| {
                try result.put(decl, {});
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
