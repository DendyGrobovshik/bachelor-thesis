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
const Variance = @import("tree.zig").Variance;

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

// not atomic!!!
// TODO: ensure that delete element is present
pub fn removeChild(parent: *TypeNode, child: *TypeNode) void {
    var childId: usize = 0;
    for (0..parent.childs.items.len) |i| {
        if (parent.childs.items[i] == child) {
            childId = i;
        }
    }
    _ = parent.childs.swapRemove(childId); // TODO: md use orderedRemove

    var parentId: usize = 0;
    for (0..child.parents.items.len) |i| {
        if (child.parents.items[i] == parent) {
            parentId = i;
        }
    }
    _ = child.parents.swapRemove(parentId);
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

// NOTE: top level variance is covariant
pub fn getAllByVariance(self: *TypeNode, variance: Variance, allocator: Allocator) EngineError!std.ArrayList(*TypeNode) {
    var typeNodes = std.AutoHashMap(*TypeNode, void).init(allocator);
    // try typeNodes.put(self, {});

    // TODO: учесть ограничения
    // TODO: proof that no recusrion occurs!!!
    switch (variance) {
        .invariant => {
            try typeNodes.put(self, {});
        },
        .covariant => {
            for ((try self.getChildsRecursively(allocator)).items) |tn| {
                try typeNodes.put(tn, {});
            }
        },
        .contravariant => {
            for ((try self.getParentsRecursively(allocator)).items) |tn| {
                try typeNodes.put(tn, {});
            }
        },
        .bivariant => {
            for ((try self.getChildsRecursively(allocator)).items) |tn| {
                try typeNodes.put(tn, {});
            }
            for ((try self.getParentsRecursively(allocator)).items) |tn| {
                try typeNodes.put(tn, {});
            }
        },
    }

    var result = std.ArrayList(*TypeNode).init(allocator);
    // try result.append(self);

    var it = typeNodes.keyIterator();
    while (it.next()) |typeNode| {
        try result.append(typeNode.*);
    }
    // TODO: free typNodes

    return result;
}

pub fn getChildsRecursively(self: *TypeNode, allocator: Allocator) Allocator.Error!std.ArrayList(*TypeNode) {
    var result = std.ArrayList(*TypeNode).init(allocator);
    try result.append(self);

    for (self.childs.items) |child| {
        const childs = try getChildsRecursively(child, allocator);
        try result.appendSlice(childs.items);
        // TODO: free
    }

    return result;
}

// TODO: extract copypaste
pub fn getParentsRecursively(self: *TypeNode, allocator: Allocator) Allocator.Error!std.ArrayList(*TypeNode) {
    var result = std.ArrayList(*TypeNode).init(allocator);
    try result.append(self);

    for (self.parents.items) |parent| {
        const childs = try getParentsRecursively(parent, allocator);
        try result.appendSlice(childs.items);
        // TODO: free
    }

    return result;
}
