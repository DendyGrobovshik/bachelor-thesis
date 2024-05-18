const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const constants = @import("constants.zig");
const main = @import("../main.zig");
const Tree = @import("./tree.zig").Tree;

pub const Cache = struct {
    const Child = struct {
        name: []const u8,
        is: bool,
    };

    head: *Node,
    tree: *Tree,
    allocator: Allocator,
    childsOf: std.StringHashMap(std.ArrayList(Child)),

    pub fn init(allocator: Allocator, tree: *Tree) !*Cache {
        const head = try Node.init(allocator, &constants.PREROOT);

        const childsOf = std.StringHashMap(std.ArrayList(Child)).init(allocator);

        const this = try allocator.create(Cache);
        this.* = .{
            .head = head,
            .tree = tree,
            .allocator = allocator,
            .childsOf = childsOf,
        };

        return this;
    }

    // TODO: move out, design driver for target language
    // TODO: A < B can be fast checked with knowing of B < A
    pub fn greater(self: *Cache, parent: *TypeNode, child: *TypeNode) !bool {
        const parentName = try parent.name();
        const childName = try child.name();

        if (parent.isUniversal()) {
            return true;
        }

        if (std.mem.eql(u8, parentName, childName)) {
            return true;
        }

        if (self.childsOf.getPtr(parentName)) |childs| {
            for (childs.items) |childCandidate| {
                if (std.mem.eql(u8, childCandidate.name, childName)) {
                    return childCandidate.is;
                }
            }

            const isParent = try self.tree.calculate(parent, child);
            try childs.append(.{ .name = childName, .is = isParent });
            return isParent;
        } else {
            var childs = std.ArrayList(Cache.Child).init(self.allocator);
            const isParent = try self.tree.calculate(parent, child);
            try childs.append(.{ .name = childName, .is = isParent });

            try self.childsOf.put(parentName, childs);

            return isParent;
        }

        unreachable;
    }
};
