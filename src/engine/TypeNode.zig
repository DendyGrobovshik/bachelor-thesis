const TypeNode = @import("TypeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const utils = @import("utils.zig");
const main = @import("../main.zig");
const tree = @import("tree.zig");
const constants = @import("constants.zig");

const AutoHashSet = utils.AutoHashSet;
const EngineError = @import("error.zig").EngineError;
const Declaration = @import("entities.zig").Declaration;
const Node = @import("Node.zig");
const Following = @import("following.zig").Following;
const TypeC = @import("../query_parser.zig").TypeC;
const Variance = @import("variance.zig").Variance;
const Shard = @import("entities.zig").Shard;
const FollowingShard = @import("entities.zig").FollowingShard;

pub usingnamespace @import("TypeNode_printing.zig");

// TypeNode represents type.
// Connected TypeNodes represent a subtyping graph.
// Universal is a supertype of any other.
// Subtyping graph is Partially ordered set. Relation is subtyping relation.
// Subtyping graph dynamically changes dynamically, but it must always be in consistent state.
// Consitant state - for any 2 TypeNode real relations(whether and how they are ordered or not) can be determined from the graph.

// Syntetic - types defined by constraints, they don't have names.
// Nominative(gnominative) - types that have names.
// These two subtyping systems are crossed:
//     e.g. `Name < Printable & Hashable` and `T < Printable & Hashable`
//     presented as: nominative and syntetic TypeNodes, where second has first one as child.
//     It represent that they are constraints equally types, but nominatively different.
//     Nominative can be substituted where syntetic is expected. And not always vice versa.
//
//     But nominative with only one supertype(universal) doesn't have syntetic parent.
//     They can be distinguished by backlink in Following.

pub const KindE = enum {
    universal, // https://en.wikipedia.org/wiki/Top_type
    syntetic, // constraints defined type
    nominative, // just nominative with no generic parameters
    gnominative, // nominative with generic parameters
    opening, // opening parenthesis
    closing, // closing parenthesis
};

pub const Kind = union(KindE) {
    universal: void,
    syntetic: void,
    nominative: []const u8,
    gnominative: []const u8, // parametrized nominative (parameter represented in other TypeNode's)
    opening: void,
    closing: void,
};

kind: Kind,

/// Direct neighbours, they can be in other Node(rly? - yes if function)
///
/// It current TypeNode represent end of function (kind==closing)
parents: AutoHashSet(*TypeNode),
childs: AutoHashSet(*TypeNode),

/// In which Node the current TypeNode is located.
of: *Node,
followings: std.ArrayList(*Following),

pub fn init(allocator: Allocator, kind: Kind, of: *Node) Allocator.Error!*TypeNode {
    const this = try allocator.create(TypeNode);

    this.* = .{
        .kind = kind,
        .parents = AutoHashSet(*TypeNode).init(allocator),
        .childs = AutoHashSet(*TypeNode).init(allocator),
        .of = of,
        .followings = std.ArrayList(*Following).init(allocator),
    };

    return this;
}

/// Kind of cartesian product.
/// Recursively returns pairs of equal TypeNodes of childs.
pub fn findMirrorShards(self: *TypeNode, reflection: *TypeNode, storage: *AutoHashSet(Shard), allocator: Allocator) EngineError!void {
    try storage.put(Shard{ .it = self, .reflection = reflection }, {});

    var selfChildsIt = self.childs.keyIterator();
    while (selfChildsIt.next()) |selfChild| {
        var reflectionChildsIt = reflection.childs.keyIterator();
        while (reflectionChildsIt.next()) |reflectionChild| {
            if (try eql(selfChild.*, reflectionChild.*, allocator)) {
                try findMirrorShards(selfChild.*, reflectionChild.*, storage, allocator);
            }
        }
    }
}

pub fn getMirrorFollowings(self: *TypeNode, reflection: *TypeNode, allocator: Allocator) EngineError!std.ArrayList(FollowingShard) {
    var followingShards = std.ArrayList(FollowingShard).init(allocator);

    for (self.followings.items) |selfFollowing| {
        for (reflection.followings.items) |reflectionFollowing| {
            if (selfFollowing.eq(reflectionFollowing)) {
                try followingShards.append(FollowingShard{ .it = selfFollowing, .reflection = reflectionFollowing });
            }
        }
    }

    return followingShards;
}

pub fn notEmpty(self: *TypeNode) bool {
    switch (self.kind) {
        .opening => {},
        .closing => {},
        else => return true,
    }

    if (self.parents.count() > 1 or self.childs.count() > 0) {
        return true;
    }

    return self.followings.items.len != 0;
}

pub fn setAsParentTo(parent: *TypeNode, child: *TypeNode) std.mem.Allocator.Error!void {
    if (parent == child) {
        return; // TODO: figure out who trigger it
    }

    try parent.childs.put(child, {});
    try child.parents.put(parent, {});
}

pub fn removeChild(parent: *TypeNode, child: *TypeNode) void {
    const r1 = parent.childs.remove(child);
    const r2 = child.parents.remove(parent);

    if (!r1 or !r2) {
        std.debug.panic("One of relations was not removed\n", .{});
    }
}

pub fn getFollowing(
    self: *TypeNode,
    backlink: ?*TypeNode,
    kind: Following.Kind,
    allocator: Allocator,
) Allocator.Error!*Following {
    for (self.followings.items) |following| {
        if (following.backlink == backlink and following.kind == kind) {
            return following;
        }
    }

    const following = try Following.init(allocator, self, backlink, kind);
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

pub fn extractAllDecls(self: *TypeNode, storage: *AutoHashSet(*Declaration)) Allocator.Error!void {
    var it = self.childs.keyIterator();
    while (it.next()) |child| {
        try extractAllDecls(child.*, storage);
    }

    for (self.followings.items) |following| {
        try following.to.extractAllDecls(storage);
    }
}

pub fn collectAllWithVariance(self: *TypeNode, variance: Variance, storage: *AutoHashSet(*TypeNode)) Allocator.Error!void {
    // std.debug.print("TypeNode.collectAllWithVariance\n", .{});
    // TODO: take care constraints
    switch (variance) {
        .invariant => {
            try storage.put(self, {});
        },
        .covariant => {
            try self.getChildsRecursively(storage);
        },
        .contravariant => {
            try self.getParentsRecursively(storage);
        },
        .bivariant => {
            try self.getChildsRecursively(storage);
            try self.getParentsRecursively(storage);
        },
    }
}

pub fn getChildsRecursively(self: *TypeNode, storage: *AutoHashSet(*TypeNode)) Allocator.Error!void {
    try storage.put(self, {});

    var it = self.childs.keyIterator();
    while (it.next()) |child| {
        try getChildsRecursively(child.*, storage);
    }
}

pub fn getParentsRecursively(self: *TypeNode, storage: *AutoHashSet(*TypeNode)) Allocator.Error!void {
    try storage.put(self, {});

    var it = self.parents.keyIterator();
    while (it.next()) |parent| {
        try getParentsRecursively(parent.*, storage);
    }
}

// TODO: equality of names a bit expensive, but it now it's the only way to handle syntetic
pub fn eql(self: *TypeNode, other: *TypeNode, allocator: Allocator) Allocator.Error!bool {
    return std.mem.eql(u8, try self.name(allocator), try other.name(allocator));
}

pub fn commonSynteticChild(x: *TypeNode, y: *TypeNode) ?*TypeNode {
    var xChildsIt = x.childs.keyIterator();
    while (xChildsIt.next()) |xChild| {
        var yChildsIt = y.childs.keyIterator();
        while (yChildsIt.next()) |yChild| {
            if (xChild.* == yChild.* and xChild.*.kind == Kind.syntetic) {
                return xChild.*;
            }
        }
    }

    return null;
}

pub fn createSynteticChild(x: *TypeNode, y: *TypeNode, of: *Node, allocator: Allocator) Allocator.Error!*TypeNode {
    const newUpperBound = try TypeNode.init(allocator, TypeNode.Kind.syntetic, of);
    try of.syntetics.append(newUpperBound);

    try x.setAsParentTo(newUpperBound);
    try y.setAsParentTo(newUpperBound);

    return newUpperBound;
}

pub fn isChildOf(self: *TypeNode, parent: *TypeNode) bool {
    var it = self.parents.keyIterator();
    while (it.next()) |next| {
        if (next.* == parent) {
            return true;
        }
    }

    return false;
}

pub fn depth(self: *TypeNode) u32 {
    if (self.of.by == &constants.PREROOT) {
        return 0;
    }

    return 1 + depth(self.of.by);
}
