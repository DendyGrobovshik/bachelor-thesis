const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const constants = @import("constants.zig");
const Tree = @import("./tree.zig").Tree;
const Server = @import("../driver/server.zig").Server;

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

    // TODO: move out, design driver for target language
    // TODO: A < B can be fast checked with knowing of B < A
    pub fn askSubtype(self: *Cache, server: *Server, parent: *TypeNode, child: *TypeNode) !bool {
        self.statistic.total = self.statistic.total + 1;

        const parentName = try parent.name(self.allocator);
        const childName = try child.name(self.allocator);

        if (parent.kind == TypeNode.Kind.universal) {
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

            const isParent = try self.askServer(server, parent, child);
            try childs.append(.{ .name = childName, .is = isParent });
            return isParent;
        } else {
            var childs = std.ArrayList(Cache.Child).init(self.allocator);

            const isParent = try self.askServer(server, parent, child);
            try childs.append(.{ .name = childName, .is = isParent });

            try self.childsOf.put(parentName, childs);

            return isParent;
        }

        unreachable;
    }

    inline fn askServer(self: *Cache, server: *Server, parent: *TypeNode, child: *TypeNode) !bool {
        self.statistic.cacheMiss = self.statistic.cacheMiss + 1;
        const isParent = try server.askSubtype(parent, child);

        return isParent;
    }
};
