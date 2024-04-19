const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const Declaration = @import("tree.zig").Declaration;
const Node = @import("node.zig").Node;
const utils = @import("utils.zig");
const String = @import("../utils.zig").String;
const TypeC = @import("../query.zig").TypeC;

pub const TypeNode = struct {
    pub const TypeNodeKind = enum {
        default,
        name,
        open,
        close,

        gin,
        gout,
        universal,

        syntetic,
    };

    pub const Of = String;

    pub const Following = struct {
        to: *Node, // to what node
        backlink: ?*TypeNode, // same as de Bruijn index (helps to disinguish generics)
    };

    of: Of,
    kind: TypeNodeKind,

    // direct neighbour, they can be in other Node
    super: std.ArrayList(*TypeNode),
    sub: std.ArrayList(*TypeNode),

    preceding: ?*Node,
    followings: std.ArrayList(*Following),

    pub fn init(allocator: Allocator, of: Of) !*TypeNode {
        const super = std.ArrayList(*TypeNode).init(allocator);
        const sub = std.ArrayList(*TypeNode).init(allocator);

        const self = try allocator.create(TypeNode);

        const followings = std.ArrayList(*Following).init(allocator);

        // TODO: try to remove the hack caused by segfault
        const newOf = try std.fmt.allocPrint(allocator, "{s}", .{of});

        self.* = .{
            .of = newOf,
            .super = super,
            .sub = sub,
            .preceding = null,
            .followings = followings,
            .kind = TypeNodeKind.default,
        };

        return self;
    }

    pub fn isSyntetic(self: *TypeNode) bool {
        switch (self.kind) {
            .syntetic => return true,
            else => return false,
        }
    }

    pub fn setAsParentTo(parent: *TypeNode, child: *TypeNode) std.mem.Allocator.Error!void {
        // TODO: add save check if it is already present
        try parent.sub.append(child);
        try child.super.append(parent);
    }

    pub fn getFollowing(self: *TypeNode, backlink: ?*TypeNode, allocator: Allocator) !*Node {
        // here, in following can be only one backlink=null,
        // that presents newly introduced generic or concrete type
        for (self.followings.items) |following| {
            if (following.backlink == backlink) {
                // `to` is never null, because it bound with backlink(existing or not)
                return following.to;
            }
        }

        std.debug.print("Allocating following from TypeNode.Of='{s}'\n", .{self.of});
        // if no candidate, then it should be added
        const following = try allocator.create(Following);
        following.to = try Node.init(allocator, self);
        following.backlink = backlink;
        try self.followings.append(following);

        return following.to;
    }

    // TODO: move out, design driver for target language
    pub fn greater(self: *TypeNode, what: *TypeNode) bool {
        if (std.mem.eql(u8, self.of, "T")) {
            return true;
        }

        if (std.mem.eql(u8, self.of, what.of)) {
            return true;
        }

        const Pair = struct { []const u8, []const u8 };

        const pairs = [_]Pair{
            .{ "Collection", "String" },
            .{ "Int", "IntEven" },
            .{ "Printable", "IntEven" },
            .{ "Printable", "Collection" },
        };

        for (pairs) |pair| {
            if (std.mem.eql(u8, self.of, pair[0]) and std.mem.eql(u8, what.of, pair[1])) {
                return true;
            }
        }

        return false;
    }

    pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator, accumulatedName: std.ArrayList(u8)) anyerror!void {
        std.debug.print("\nDrawing typeNode {s} with {} subs and {} followings\n", .{ self.of, self.sub.items.len, self.followings.items.len });

        const name = if (std.mem.eql(u8, self.of, "?")) "syntetic" else self.of;
        const typeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, name });

        var backlinkFollowingId: usize = 0;
        if (self.preceding) |preceding| {
            backlinkFollowingId = utils.getBacklinkFollowingId(preceding);
        }

        for (self.followings.items, 0..) |following, followingId| {
            var nextNodeAccumulatedName = try accumulatedName.clone();

            try nextNodeAccumulatedName.appendSlice("functionarrow322");

            try nextNodeAccumulatedName.appendSlice(name);
            const nextNodeId = try std.fmt.allocPrint(allocator, "{s}T", .{nextNodeAccumulatedName.items});

            const toNextNode = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[lhead = cluster_{s}{}];\n", .{ typeNodeId, backlinkFollowingId, nextNodeId, followingId, nextNodeAccumulatedName.items, followingId });
            try file.writeAll(toNextNode);

            try following.to.draw(file, allocator, nextNodeAccumulatedName);
        }

        std.debug.print("Super nodes {}\n", .{self.super.items.len});
        next_super: for (self.super.items) |super| {
            switch (super.kind) {
                .close => {
                    try drawLongJump(file, allocator, super, try getOpenInThisNode(self), accumulatedName, typeNodeId);
                    break :next_super;
                },
                else => {},
            }

            const superName = if (std.mem.eql(u8, super.of, "?")) "syntetic" else super.of;
            const superTypeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, superName });

            const fromSuper = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[color=red,style=filled];\n", .{ superTypeNodeId, backlinkFollowingId, typeNodeId, backlinkFollowingId });
            try file.writeAll(fromSuper);
        }
    }

    fn getOpenInThisNode(self: *TypeNode) Node.NodeError!*TypeNode {
        var current = self;

        while (true) {
            std.debug.print("GOUP {s} {}\n", .{ current.of, current.kind });
            switch (current.kind) {
                .universal => break,
                else => {},
            }

            for (current.super.items) |super| {
                switch (super.kind) {
                    .close => {},
                    else => current = super,
                }
            }
        }

        std.debug.print("GO {s} {}\n", .{ current.of, current.sub.items.len });

        for (current.sub.items) |mbOpen| {
            std.debug.print("GODO {}\n", .{mbOpen.kind});
            switch (mbOpen.kind) {
                .open => return mbOpen,
                else => {},
            }
        }

        return Node.NodeError.ShouldBeUnreachable;
    }

    // TODO: this is really dump hack, definitely should be fixed
    fn drawLongJump(
        file: std.fs.File,
        allocator: Allocator,
        end: *TypeNode,
        current: *TypeNode,
        accumulatedName: std.ArrayList(u8),
        targetId: []const u8,
    ) anyerror!void {
        std.debug.print("draw long jump {s}\n", .{current.of});

        if (current == end) {
            std.debug.print("FOUND!!!\n", .{});

            const currentId = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                accumulatedName.items,
                current.of,
            });

            var backlinkFollowingId: usize = 0;
            if (current.preceding) |preceding| {
                backlinkFollowingId = utils.getBacklinkFollowingId(preceding);
            }

            const fromSuper = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[color=red,style=filled];\n", .{
                currentId,
                backlinkFollowingId,
                targetId,
                backlinkFollowingId,
            });
            try file.writeAll(fromSuper);
        }

        var candidates = std.ArrayList(*TypeNode).init(allocator);
        for (current.followings.items) |following| {
            const universal = following.to.universal;

            for (universal.sub.items) |sub| {
                try candidates.append(sub);
            }
        }

        for (candidates.items) |nextTypeNode| {
            var nextAccumulatedName = try accumulatedName.clone();

            try nextAccumulatedName.appendSlice("functionarrow322");

            const name = if (std.mem.eql(u8, current.of, "?")) "syntetic" else current.of;
            try nextAccumulatedName.appendSlice(name);

            try drawLongJump(file, allocator, end, nextTypeNode, nextAccumulatedName, targetId);
        }
    }
};
