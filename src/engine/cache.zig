const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const tree = @import("tree.zig");
const subtyping = @import("subtyping.zig");
const main = @import("../main.zig");

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const constants = @import("constants.zig");
const Tree = @import("./tree.zig").Tree;
const Server = @import("../driver/server.zig").Server;
const EngineError = @import("error.zig").EngineError;

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

    /// TypeNode arguements are from tree not from cache
    ///
    // TODO: A < B can be fast checked with knowing of B < A
    pub fn isSubtype(childFromTree: *TypeNode, parentFromTree: *TypeNode) EngineError!bool {
        // std.debug.print("Cache.isSubtype\n", .{});

        const self = tree.current.cache;

        self.statistic.total = self.statistic.total + 1;

        if (childFromTree.of == parentFromTree.of and parentFromTree.kind == TypeNode.Kind.universal) {
            return true;
        }

        const childFromCache = try self.mirror(childFromTree);
        const parentFromCache = try self.mirror(parentFromTree);

        return subtyping.isInUpperBounds(parentFromCache, childFromCache);
    }

    /// searches and adds if necessary TypeNode in cache semantically identical to `target` from tree
    ///
    /// This is another mirror.
    fn mirror(self: *Cache, target: *TypeNode) EngineError!*TypeNode {
        // TODO: handle if TypeNode is for function
        // const node = try self.mirrorNode(target.of);
        const node = self.head;

        switch (target.kind) {
            .universal => {
                return node.universal;
            },
            .gnominative, .nominative => {
                const name = switch (target.kind) {
                    .gnominative => target.kind.gnominative,
                    .nominative => target.kind.nominative,
                    else => unreachable,
                };
                // std.debug.print("NAME: {s}\n", .{name});

                if (node.named.get(name)) |existing| {
                    return existing;
                } else {
                    const newTypeNode = try TypeNode.init(self.allocator, target.kind, node);

                    try node.named.put(name, newTypeNode);

                    try subtyping.insertNominative(newTypeNode, node, askOracle, self.allocator); // TODO: create arena and free after?

                    return newTypeNode;
                }
            },
            .syntetic => {
                var constraints = try subtyping.getMinorantOfNominativeUpperBounds(target, self.allocator);
                return try subtyping.solveConstraintsDefinedPosition(node, &constraints, self.allocator);
            },
            .opening => {
                return node.opening;
            },
            .closing => {
                return node.closing;
            },
        }
    }

    fn mirrorNode(self: *Cache, target: *Node) EngineError!*Node {
        if (target.by == &constants.PREROOT) {
            return self.head;
        }

        const by = try self.mirror(target.by);
        return by.of;
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
};
