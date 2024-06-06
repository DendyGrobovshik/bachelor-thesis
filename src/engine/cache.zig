const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const tree = @import("tree.zig");
const subtyping = @import("subtyping.zig");
const main = @import("../main.zig");
const constants = @import("constants.zig");
const queryParser = @import("../query_parser.zig");
const walker = @import("walker.zig");

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const Tree = @import("./tree.zig").Tree;
const Server = @import("../driver/server.zig").Server;
const EngineError = @import("error.zig").EngineError;
const AutoHashSet = utils.AutoHashSet;
const Variance = @import("variance.zig").Variance;
const Following = @import("following.zig").Following;

pub const Cache = struct {
    const Child = struct {
        name: []const u8,
        is: bool,
    };

    const Statistic = struct {
        cacheMiss: i32,
        total: i32,

        pub fn print(self: Statistic) void {
            if (self.total == 0) {
                std.debug.print("Cache was not used\n", .{});
                return;
            }

            std.debug.assert(self.total > self.cacheMiss);

            const percent = @divTrunc(self.cacheMiss * 100, self.total);
            std.debug.print("Cache miss = {}% [{}/{}]\n", .{ percent, self.cacheMiss, self.total });
        }
    };

    statistic: Statistic,
    head: *Node,
    allocator: Allocator,
    childsOf: std.StringHashMap(std.ArrayList(Child)),

    pub fn init(allocator: Allocator) !*Cache {
        const head = try Node.init(allocator, &constants.PREROOT);

        const childsOf = std.StringHashMap(std.ArrayList(Child)).init(allocator);

        const this = try allocator.create(Cache);
        this.* = .{
            .head = head,
            .allocator = allocator,
            .childsOf = childsOf,
            .statistic = Statistic{ .cacheMiss = 0, .total = 0 },
        };

        return this;
    }

    /// TypeNode arguements are from tree not from cache.
    ///
    // TODO: A < B can be fast checked with knowing of B < A
    pub fn isSubtype(childFromTree: *TypeNode, parentFromTree: *TypeNode) EngineError!bool {
        if (childFromTree.kind == TypeNode.Kind.opening or
            parentFromTree.kind == TypeNode.Kind.opening)
        {
            return false;
        }

        const cache = tree.current.cache;
        // std.debug.print("Cache.isSubtype '{s}' < '{s}'\n", .{
        //     try childFromTree.name(cache.allocator),
        //     try parentFromTree.name(cache.allocator),
        // });

        cache.statistic.total = cache.statistic.total + 1;

        if (childFromTree.of == parentFromTree.of and parentFromTree.kind == TypeNode.Kind.universal) {
            return true;
        }
        if (childFromTree.kind == TypeNode.Kind.syntetic or parentFromTree.kind == TypeNode.Kind.syntetic) {
            // TODO: it's not clear whether here should be checked minorants of nominative upper bounds
            // NOTE: it's better proof and describe other invariants
            return false;
        }

        const childFromCache = try walker.mirrorFromTreeToCache(childFromTree, cache.allocator) orelse return false;
        const parentFromCache = try walker.mirrorFromTreeToCache(parentFromTree, cache.allocator) orelse return false;

        return subtyping.isInUpperBounds(parentFromCache, childFromCache);
    }


    fn askOracle(child: *TypeNode, parent: *TypeNode) EngineError!bool {
        if ((child.kind == TypeNode.Kind.opening or
            parent.kind == TypeNode.Kind.opening or
            child.kind == TypeNode.Kind.closing or
            parent.kind == TypeNode.Kind.closing))
        {
            return false;
        }

        const self = tree.current.cache;

        self.statistic.total = self.statistic.total + 1;
        self.statistic.cacheMiss = self.statistic.cacheMiss + 1;

        if (tree.current.server) |oracle| {
            return try oracle.isSubtype(child, parent);
        } else {
            return utils.defaultSubtype(try parent.name(self.allocator), try child.name(self.allocator));
        }
    }

    /// Ask oracle about parents of `ty` and set them.
    /// `ty` - TypeNode in cache.
    /// In case no server-client driver established, default `utils.getParentsOfType` oracle is used.
    pub fn setParentsTo(ty: *TypeNode) EngineError!void {
        const cache = tree.current.cache;

        cache.statistic.total = cache.statistic.total + 1;
        cache.statistic.cacheMiss = cache.statistic.cacheMiss + 1;

        const tyStr = try utils.typeToString(ty, cache.allocator, true);

        var rawTypes: []const []const u8 = undefined;
        if (tree.current.server) |oracle| {
            rawTypes = try oracle.getParentsOf(tyStr.str);
        } else {
            rawTypes = try utils.getParentsOfType(tyStr.str);
        }

        var result = AutoHashSet(*TypeNode).init(cache.allocator);
        for (rawTypes) |rawType| {
            const query = try queryParser.parseQuery(cache.allocator, rawType);
            const searchConfig = .{ .variance = Variance.invariant, .insert = true }; // TODO: check 'insert'
            try cache.head.searchWithVariance(query.ty, searchConfig, &result, cache.allocator);
        }

        var it = result.keyIterator();
        while (it.next()) |parent| {
            try parent.*.setAsParentTo(ty);
        }
    }
};
