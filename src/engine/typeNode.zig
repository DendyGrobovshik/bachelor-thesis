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

        if (self.parents.items.len > 1 or self.childs.items.len > 0) {
            return true;
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
            .syntetic => "syntetic",
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

    pub fn isOpening(self: *TypeNode) bool {
        return switch (self.kind) {
            .opening => true,
            else => false,
        };
    }

    pub fn isClosing(self: *TypeNode) bool {
        return switch (self.kind) {
            .closing => true,
            else => false,
        };
    }

    pub fn isGnominative(self: *TypeNode) bool {
        return switch (self.kind) {
            .gnominative => true,
            else => false,
        };
    }

    pub fn extractAllDecls(self: *TypeNode, allocator: Allocator) Allocator.Error!std.ArrayList(*Declaration) {
        var result = std.ArrayList(*Declaration).init(allocator);

        for (self.childs.items) |child| {
            try result.appendSlice((try child.extractAllDecls(allocator)).items);
        }

        for (self.followings.items) |following| {
            try result.appendSlice((try following.to.extractAllDecls(allocator)).items);
        }

        return result;
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
};
