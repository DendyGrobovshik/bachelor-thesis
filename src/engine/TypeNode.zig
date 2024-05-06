const TypeNode = @import("TypeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const EngineError = @import("error.zig").EngineError;
const Declaration = @import("tree.zig").Declaration;
const Node = @import("Node.zig");
const Following = @import("following.zig").Following;
const utils = @import("utils.zig");
const String = @import("../utils.zig").String;
const TypeC = @import("../query.zig").TypeC;
const main = @import("../main.zig");

pub usingnamespace @import("TypeNode_printing.zig");

pub const KindE = enum {
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

pub fn setAsParentTo(parent: *TypeNode, child: *TypeNode) std.mem.Allocator.Error!void {
    // TODO: check if it is already present
    try parent.childs.append(child);
    try child.parents.append(parent);
}

pub fn getFollowing(self: *TypeNode, backlink: ?*TypeNode, kind: Following.Kind, allocator: Allocator) !*Following {
    // here, in following can be only one backlink=null,
    // that presents newly introduced generic or concrete type
    for (self.followings.items) |following| {
        if (following.backlink == backlink and following.kind == kind) {
            return following;
        }
    }

    // if no candidate, then it should be added
    const following = try Following.init(allocator, self, backlink);
    following.kind = kind;
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
        try result.appendSlice((try extractAllDecls(child, allocator)).items);
    }

    for (self.followings.items) |following| {
        try result.appendSlice((try following.to.extractAllDecls(allocator)).items);
    }

    return result;
}

// TODO: move out, design driver for target language
pub fn greater(self: *TypeNode, what: *TypeNode) !bool {
    if (self.isUniversal()) {
        return true;
    }

    if (std.mem.eql(u8, try self.name(), try what.name())) {
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
        if (std.mem.eql(u8, try self.name(), pair[0]) and std.mem.eql(u8, try what.name(), pair[1])) {
            return true;
        }
    }

    return false;
}
