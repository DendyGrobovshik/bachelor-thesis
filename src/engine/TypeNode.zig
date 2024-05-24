const TypeNode = @import("TypeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const utils = @import("utils.zig");
const main = @import("../main.zig");

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

pub fn init(allocator: Allocator, kind: Kind, of: *Node) EngineError!*TypeNode {
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

pub fn getFollowing(self: *TypeNode, backlink: ?*TypeNode, kind: Following.Kind, allocator: Allocator) !*Following {
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

// NOTE: top level variance is covariant
pub fn getAllByVariance(self: *TypeNode, variance: Variance, allocator: Allocator) EngineError!std.ArrayList(*TypeNode) {
    var typeNodes = AutoHashSet(*TypeNode).init(allocator);

    // TODO: take care constraints
    switch (variance) {
        .invariant => {
            try typeNodes.put(self, {});
        },
        .covariant => {
            try self.getChildsRecursively(&typeNodes);
        },
        .contravariant => {
            try self.getParentsRecursively(&typeNodes);
        },
        .bivariant => {
            try self.getChildsRecursively(&typeNodes);
            try self.getParentsRecursively(&typeNodes);
        },
    }

    var result = std.ArrayList(*TypeNode).init(allocator);

    var it = typeNodes.keyIterator();
    while (it.next()) |typeNode| {
        try result.append(typeNode.*);
    }
    // TODO: free typNodes

    return result;
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
