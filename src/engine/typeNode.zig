const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const EngineError = @import("error.zig").EngineError;
const Declaration = @import("tree.zig").Declaration;
const Node = @import("node.zig").Node;
const Following = @import("following.zig").Following;
const utils = @import("utils.zig");
const String = @import("../utils.zig").String;
const TypeC = @import("../query.zig").TypeC;
const main = @import("../main.zig");

pub var PREROOT: TypeNode = undefined;

pub const TypeNode = struct {
    const KindE = enum {
        universal, // https://en.wikipedia.org/wiki/Top_type
        syntetic, // consstraints defined type
        nominative, // just nominative with no generic parameters
        gnominative, // nominative with generic parameters
        opening, // opening parenthesis
        closing, // closing parenthesis
    };

    pub const Kind = union(KindE) {
        universal: void,
        syntetic: void,
        nominative: []const u8,
        gnominative: []const u8,
        // generic: void,
        opening: void,
        closing: void,
    };

    kind: Kind,

    // direct neighbour, they can be in other Node(rly? - yes if function)
    parents: std.ArrayList(*TypeNode),
    childs: std.ArrayList(*TypeNode),

    of: *Node,
    followings: std.ArrayList(*Following),

    pub fn init(allocator: Allocator, kind: Kind, of: *Node) EngineError!*TypeNode {
        const parents = std.ArrayList(*TypeNode).init(allocator);
        const childs = std.ArrayList(*TypeNode).init(allocator);

        const self = try allocator.create(TypeNode);

        const followings = std.ArrayList(*Following).init(allocator);

        // TODO: try to remove the hack caused by segfault
        // const newOf = try std.fmt.allocPrint(allocator, "{s}", .{of});

        self.* = .{
            .kind = kind,
            .parents = parents,
            .childs = childs,
            .of = of,
            .followings = followings,
        };

        return self;
    }

    pub fn notEmpty(self: *TypeNode) bool {
        switch (self.kind) {
            .opening => {},
            .closing => {},
            else => return true,
        }

        return self.followings.items.len != 0;
    }

    pub fn name(self: *TypeNode) []const u8 {
        return switch (self.kind) {
            .universal => "U",
            .syntetic => self.synteticName(),
            .nominative => self.kind.nominative,
            .gnominative => self.kind.gnominative,
            .opening => "opening322",
            .closing => "closing322",
        };
    }

    pub fn labelName(self: *TypeNode) []const u8 {
        return switch (self.kind) {
            .universal => "U",
            .syntetic => self.synteticName(),
            .nominative => self.kind.nominative,
            .gnominative => self.kind.gnominative,
            .opening => "(",
            .closing => ")",
        };
    }

    pub fn color(self: *TypeNode) []const u8 {
        return switch (self.kind) {
            .universal => "yellow",
            .syntetic => "blue",
            .nominative => "lightgrey",
            .gnominative => "purple",
            .opening => "sienna",
            .closing => "sienna",
        };
    }

    fn synteticName(self: *TypeNode) []const u8 {
        var result = std.ArrayList(u8).init(std.heap.page_allocator); // TODO:

        for (self.parents.items[0 .. self.parents.items.len - 1]) |parent| {
            result.appendSlice(parent.name()) catch unreachable;
            result.appendSlice("and") catch unreachable;
        }

        result.appendSlice(self.parents.getLast().name()) catch unreachable;

        return result.items; // TODO: check allocator releasing
    }

    pub fn setAsParentTo(parent: *TypeNode, child: *TypeNode) std.mem.Allocator.Error!void {
        // TODO: check if it is already present
        try parent.childs.append(child);
        try child.parents.append(parent);
    }

    pub fn getFollowing(self: *TypeNode, backlink: ?*TypeNode, allocator: Allocator) !*Following {
        // here, in following can be only one backlink=null,
        // that presents newly introduced generic or concrete type
        for (self.followings.items) |following| {
            if (following.backlink == backlink) {
                return following;
            }
        }

        // if no candidate, then it should be added
        const following = try Following.init(allocator, self, backlink);
        try self.followings.append(following);

        return following;
    }

    /// Assume that self is closing parenthesis
    /// And that here is 2-arity function type between (T -> Array) (Array<T>)
    /// Return the arrow
    pub fn genericFollowing(self: *TypeNode) *Following { // TODO: check if it works correctly when gnominative have constraints
        const gnominative = self.of.by;
        const generic = gnominative.of.by;

        for (generic.followings.items) |following| {
            if (following.to == gnominative.of) {
                return following;
            }
        }

        // TODO: check in case of paralell modification
        unreachable;
    }

    pub fn isSyntetic(self: *TypeNode) bool {
        return switch (self.kind) {
            .syntetic => true,
            else => false,
        };
    }

    pub fn isUniversal(self: *TypeNode) bool {
        return switch (self.kind) {
            .universal => true,
            else => false,
        };
    }

    // TODO: move out, design driver for target language
    pub fn greater(self: *TypeNode, what: *TypeNode) bool {
        if (self.isUniversal()) {
            return true;
        }

        if (std.mem.eql(u8, self.name(), what.name())) {
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
            if (std.mem.eql(u8, self.name(), pair[0]) and std.mem.eql(u8, what.name(), pair[1])) {
                return true;
            }
        }

        return false;
    }

    pub fn fullPathName(self: *TypeNode) anyerror![]const u8 {
        return try std.fmt.allocPrint(main.gallocator, "{s}{s}", .{ try self.of.fullPathName(), self.name() });
    }

    pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator) anyerror!void {
        try file.writeAll(try std.fmt.allocPrint(allocator, "{s}[label=\"{s}\",color={s},style=filled];\n", .{
            try self.fullPathName(),
            self.labelName(),
            self.color(),
        }));
    }

    pub fn drawConnections(self: *TypeNode, file: std.fs.File, allocator: Allocator) !void {
        for (self.childs.items) |child| {
            if (child.notEmpty()) {
                try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[color=red,style=filled];\n", .{
                    try self.fullPathName(),
                    try child.fullPathName(),
                }));
            }
        }

        for (self.followings.items) |following| {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[lhead=cluster_{s},color=\"{s}\",style=filled];\n", .{
                try self.fullPathName(),
                try following.to.universal.fullPathName(),
                try following.to.fullPathName(),
                following.color(),
            }));

            try following.to.draw(file, allocator);
        }
    }

    // pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator, accumulatedName: std.ArrayList(u8)) anyerror!void {
    //     std.debug.print("\nDrawing typeNode {s} with {} subs and {} followings\n", .{ self.of, self.childs.items.len, self.followings.items.len });

    //     const name = if (std.mem.eql(u8, self.of, "?")) "syntetic" else self.of;
    //     const typeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, name });

    //     var backlinkFollowingId: usize = 0;
    //     if (self.curNode) |preceding| {
    //         backlinkFollowingId = utils.getBacklinkFollowingId(preceding);
    //     }

    //     for (self.followings.items, 0..) |following, followingId| {
    //         var nextNodeAccumulatedName = try accumulatedName.clone();

    //         var nameWasTransformed = false;

    //         if (self.isGout()) {
    //             nameWasTransformed = true;
    //             std.debug.print("HERE IT IS: {s}\n", .{nextNodeAccumulatedName.items});
    //             const start = std.mem.lastIndexOf(u8, nextNodeAccumulatedName.items, "functionopening322").? + 34;
    //             std.debug.print("drop start {s}\n", .{nextNodeAccumulatedName.items[start..]});

    //             const genericNominativeName = try std.fmt.allocPrint(allocator, "{s}leftangle322{s}rightangle322", .{ name, nextNodeAccumulatedName.items[start..] });
    //             std.debug.print("TRE {s}\n", .{genericNominativeName});
    //             try nextNodeAccumulatedName.replaceRange(start - 34, nextNodeAccumulatedName.items.len - start + 34, genericNominativeName);
    //         }

    //         if (!nameWasTransformed) {
    //             // if (!(self.isClosing() and utils.endsWithRightAngle(nextNodeAccumulatedName.items))) {
    //             try nextNodeAccumulatedName.appendSlice("functionarrow322");

    //             try nextNodeAccumulatedName.appendSlice(name);
    //             // }
    //         }

    //         const nextNodeId = try std.fmt.allocPrint(allocator, "{s}T", .{nextNodeAccumulatedName.items});

    //         const toNextNode = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[lhead = cluster_{s}{}];\n", .{ typeNodeId, backlinkFollowingId, nextNodeId, followingId, nextNodeAccumulatedName.items, followingId });
    //         try file.writeAll(toNextNode);

    //         try following.to.draw(file, allocator, nextNodeAccumulatedName);
    //     }

    //     std.debug.print("Super nodes {}\n", .{self.parents.items.len});
    //     next_super: for (self.parents.items) |super| {
    //         switch (super.kind) {
    //             .close => {
    //                 try drawLongJump(file, allocator, super, try getOpenInThisNode(self), accumulatedName, typeNodeId);
    //                 break :next_super;
    //             },
    //             else => {},
    //         }

    //         const superName = if (std.mem.eql(u8, super.of, "?")) "syntetic" else super.of;
    //         const superTypeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, superName });

    //         const fromSuper = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[color=red,style=filled];\n", .{ superTypeNodeId, backlinkFollowingId, typeNodeId, backlinkFollowingId });
    //         try file.writeAll(fromSuper);
    //     }
    // }

    // fn getOpenInThisNode(self: *TypeNode) Node.EngineError!*TypeNode {
    //     var current = self;

    //     while (true) {
    //         std.debug.print("GOUP {s} {}\n", .{ current.of, current.kind });
    //         switch (current.kind) {
    //             .universal => break,
    //             else => {},
    //         }

    //         for (current.parents.items) |super| {
    //             switch (super.kind) {
    //                 .close => {},
    //                 else => current = super,
    //             }
    //         }
    //     }

    //     std.debug.print("GO {s} {}\n", .{ current.of, current.childs.items.len });

    //     for (current.childs.items) |mbOpen| {
    //         std.debug.print("GODO {}\n", .{mbOpen.kind});
    //         switch (mbOpen.kind) {
    //             .open => return mbOpen,
    //             else => {},
    //         }
    //     }

    //     return Node.EngineError.ShouldBeUnreachable;
    // }

    // // TODO: this is really dump hack, definitely should be fixed
    // fn drawLongJump(
    //     file: std.fs.File,
    //     allocator: Allocator,
    //     end: *TypeNode,
    //     current: *TypeNode,
    //     accumulatedName: std.ArrayList(u8),
    //     targetId: []const u8,
    // ) anyerror!void {
    //     std.debug.print("draw long jump {s}\n", .{current.of});

    //     if (current == end) {
    //         std.debug.print("FOUND!!!\n", .{});

    //         const currentId = try std.fmt.allocPrint(allocator, "{s}{s}", .{
    //             accumulatedName.items,
    //             current.of,
    //         });

    //         var backlinkFollowingId: usize = 0;
    //         if (current.curNode) |preceding| {
    //             backlinkFollowingId = utils.getBacklinkFollowingId(preceding);
    //         }

    //         const fromSuper = try std.fmt.allocPrint(allocator, "{s}{} -> {s}{}[color=red,style=filled];\n", .{
    //             currentId,
    //             backlinkFollowingId,
    //             targetId,
    //             backlinkFollowingId,
    //         });
    //         try file.writeAll(fromSuper);
    //     }

    //     var candidates = std.ArrayList(*TypeNode).init(allocator);
    //     for (current.followings.items) |following| {
    //         const universal = following.to.universal;

    //         for (universal.sub.items) |sub| {
    //             try candidates.append(sub);
    //         }
    //     }

    //     for (candidates.items) |nextTypeNode| {
    //         var nextAccumulatedName = try accumulatedName.clone();

    //         const name = if (std.mem.eql(u8, current.of, "?")) "syntetic" else current.of;

    //         var nameWasTransformed = false;
    //         if (std.mem.eql(u8, nextTypeNode.of, "functionclosing322")) {
    //             if (current.isGout()) {
    //                 std.debug.print("HERE2 IT IS: {s}\n", .{nextAccumulatedName.items});
    //                 nameWasTransformed = true;
    //                 const start = std.mem.lastIndexOf(u8, nextAccumulatedName.items, "functionopening322").? + 34;
    //                 std.debug.print("REST {s}\n", .{nextAccumulatedName.items[start..]});
    //                 // const arrow = std.mem.lastIndexOf(u8, nextAccumulatedName.items[start..], "functionarrow322").?;
    //                 // std.debug.print("FROM {}\n", .{start});
    //                 std.debug.print("IN ANGLE NAME '{s}'\n", .{nextAccumulatedName.items[start..]});

    //                 const genericNominativeName = try std.fmt.allocPrint(allocator, "{s}leftangle322{s}rightangle322", .{
    //                     current.of,
    //                     nextAccumulatedName.items[start..],
    //                 });
    //                 std.debug.print("TRE {s}\n", .{genericNominativeName});
    //                 try nextAccumulatedName.replaceRange(start - 34, nextAccumulatedName.items.len - start + 34, genericNominativeName);
    //             }
    //             std.debug.print("BEE {s}\n", .{nextAccumulatedName.items});
    //         }

    //         if (!nameWasTransformed) {
    //             // if (!(current.isClosing() and utils.endsWithRightAngle(nextAccumulatedName.items))) {
    //             try nextAccumulatedName.appendSlice("functionarrow322");
    //             try nextAccumulatedName.appendSlice(name);
    //             // }
    //             std.debug.print("NEE {s}\n", .{name});
    //         }

    //         try drawLongJump(file, allocator, end, nextTypeNode, nextAccumulatedName, targetId);
    //     }
    // }
};
