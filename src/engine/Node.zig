const Node = @import("Node.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const utils = @import("utils.zig");
const main = @import("../main.zig");
const tree = @import("tree.zig");
const subtyping = @import("subtyping.zig");
const defaultVariances = @import("variance.zig").defaultVariances;
const walker = @import("walker.zig");

const AutoHashSet = utils.AutoHashSet;
const EngineError = @import("error.zig").EngineError;
const TypeNode = @import("TypeNode.zig");
const Declaration = @import("entities.zig").Declaration;
const Function = @import("../query_parser.zig").Function;
const Type = @import("../query_parser.zig").Type;
const TypeC = @import("../query_parser.zig").TypeC;
const Constraint = @import("../query_parser.zig").Constraint;
const Following = @import("following.zig").Following;
const Variance = @import("variance.zig").Variance;
const Shard = @import("entities.zig").Shard;
const FollowingShard = @import("entities.zig").FollowingShard;
const Mirror = @import("entities.zig").Mirror;
const Cache = @import("cache.zig").Cache;

const LOG = @import("config").logp;

// NOTE: all the decls become public
pub usingnamespace @import("Node_printing.zig");

named: std.StringHashMap(*TypeNode),
syntetics: std.ArrayList(*TypeNode),

universal: *TypeNode,
opening: *TypeNode,
closing: *TypeNode,

endings: std.ArrayList(*Declaration),
by: *TypeNode,

pub fn init(allocator: Allocator, by: *TypeNode) Allocator.Error!*Node {
    const self = try allocator.create(Node);

    const universal = try TypeNode.init(allocator, TypeNode.Kind.universal, self);
    const opening = try TypeNode.init(allocator, TypeNode.Kind.opening, self);
    const closing = try TypeNode.init(allocator, TypeNode.Kind.closing, self);

    // Semantically closing can not be subtype of universal,
    // because even if it represent type (from matching previous opening) that belongs to other Node.
    // it's subtype of other Node. Same for opening (it doesn't represent type, just part of it).

    self.* = .{
        .named = std.StringHashMap(*TypeNode).init(allocator),
        .syntetics = std.ArrayList(*TypeNode).init(allocator),
        .endings = std.ArrayList(*Declaration).init(allocator),
        .universal = universal,
        .opening = opening,
        .closing = closing,
        .by = by,
    };

    return self;
}

// return leafs of equal(up to variance) paths from reflections
// "up to" should be taken figuratively
pub fn mirrorWalk(self: *Node, reflection: *Node, storage: *AutoHashSet(Mirror), allocator: Allocator) EngineError!void {
    var shards = AutoHashSet(Shard).init(allocator);
    try self.universal.findMirrorShards(reflection.universal, &shards, allocator);
    try self.closing.findMirrorShards(reflection.closing, &shards, allocator);
    try self.opening.findMirrorShards(reflection.opening, &shards, allocator);

    try storage.put(Mirror{ .it = self, .reflection = reflection }, {});

    var shardsIt = shards.keyIterator();
    while (shardsIt.next()) |shard| { // TODO: variance
        var childs = AutoHashSet(*TypeNode).init(allocator);
        try shard.*.it.getChildsRecursively(&childs);

        var parents = AutoHashSet(*TypeNode).init(allocator);
        try shard.*.reflection.getParentsRecursively(&parents);

        var childsIt = childs.keyIterator();
        while (childsIt.next()) |child| {
            var parentsIt = parents.keyIterator();
            while (parentsIt.next()) |parent| {
                const mirrorFollowings = try child.*.getMirrorFollowings(parent.*, allocator);

                for (mirrorFollowings.items) |mirrorFollowing| {
                    try mirrorWalk(
                        mirrorFollowing.it.to,
                        mirrorFollowing.reflection.to,
                        storage,
                        allocator,
                    );
                }
            }
        }
    }
}

pub const SearchConfig = struct {
    variance: Variance,
    insert: bool,
};

/// Do search TypeNode exactly matching `next` type. Do not insert extra nodes.
pub fn search(self: *Node, next: *TypeC, config: SearchConfig, allocator: Allocator) EngineError!?*TypeNode {
    var storage = AutoHashSet(*TypeNode).init(allocator); // TODO: free

    try self.searchWithVariance(next, config, &storage, allocator);

    std.debug.assert(storage.count() <= 1);

    var it = storage.keyIterator();
    if (it.next()) |res| {
        return res.*;
    } else {
        return null;
    }
}

// TODO: distinguish allocation while inserting
// do exact search or insert if no present
pub fn searchWithVariance(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("searchWithVariance: {s} {} node:{s}\n", .{ next.ty, config.variance, try self.labelName(allocator) });
    switch (next.ty.*) {
        .nominative => try self.searchNominative(next, config, storage, allocator),
        .function => try self.searchFunction(next, config, storage, allocator),
        .list => try self.searchList(next, config, storage, allocator),
    }
}

pub fn searchNominative(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("searchNominative: {s}\n", .{next.ty});
    if (next.ty.nominative.generic) |_| {
        try self.searchNominativeWithGeneric(next, config, storage, allocator);
        return;
    }

    if (next.ty.nominative.isGeneric()) {
        const nextConfig = .{ .variance = config.variance.x(defaultVariances.nominativeGeneric), .insert = config.insert };

        try self.searchGeneric(next, nextConfig, storage, allocator);
    } else {
        if (self.named.get(next.ty.nominative.name)) |typeNode| {
            try typeNode.collectAllWithVariance(config.variance, storage);
        } else if (config.insert) {
            const typeNode = try self.createAndInsertNominative(next, allocator);
            try typeNode.collectAllWithVariance(config.variance, storage);
        }
    }
}

fn createAndInsertNominative(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    // std.debug.print("createAndInsertNamed\n", .{});
    const name = try utils.simplifyName(next.ty.nominative.name, allocator);

    const kind: TypeNode.Kind = if (next.ty.nominative.hadGeneric) .{ .gnominative = name } else .{ .nominative = name };
    const newTypeNode = try TypeNode.init(allocator, kind, self);

    try self.named.put(name, newTypeNode);

    if (kind != TypeNode.Kind.gnominative) {
        // because of for gnominative it makes sense to check subtyping only between
        // for whole type (e.g. 'Array<T>') not only for 'Array', so this operation
        // performed where gnoninative transformed into function (like 'T -> Array'
        try subtyping.insertNominative(newTypeNode, self, Cache.isSubtype, allocator);
    } else {
        // TODO: but what about hierarchy between gnominatives (between universal?)
        try self.universal.setAsParentTo(newTypeNode); // probably they should be distinguished (mb gnominatives array)
        // for now it's required in searching
    }

    return newTypeNode;
}

pub fn searchGeneric(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    var parents = AutoHashSet(*TypeNode).init(allocator);

    // generic are only constraint defined, and it requires another inserting algorithm
    for (next.constraints.items) |constraint| {
        for (constraint.superTypes.items) |superType| {
            const nextConfig = .{
                .variance = Variance.invariant, // TODO: why?
                .insert = config.insert,
            };
            try self.searchWithVariance(superType, nextConfig, &parents, allocator);
        }
    }

    // TODO: how to handle consfig.insert=false here???
    const result = try subtyping.solveConstraintsDefinedPosition(self, &parents, allocator);

    if (next.ty.nominative.typeNode) |backlink| {
        const following = try allocator.create(Following);
        following.to = try Node.init(allocator, result);
        following.backlink = backlink;
        try result.followings.append(following);
    } else {
        next.ty.nominative.typeNode = result;
    }

    try result.collectAllWithVariance(config.variance, storage);
}

/// unpacks `Nominantive<T>` to function `T -> Nominative_`
pub fn searchNominativeWithGeneric(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("Searching nominative with generic \n", .{});
    const generic = next.ty.nominative.generic orelse unreachable;

    // removing generic to escape recursive loop
    const newNextType = try allocator.create(Type);
    newNextType.* = .{ .nominative = .{
        .name = next.ty.nominative.name,
        .generic = null,
        .hadGeneric = true,
    } };

    const from = switch (generic.ty.*) {
        .list => generic,
        .nominative => generic,
        .function => generic,
    };

    const ty = try allocator.create(Type);
    ty.* = .{ .function = .{
        .from = from,
        .to = try TypeC.init(allocator, newNextType),
    } };

    const typec = try TypeC.init(allocator, ty);

    // TODO: handle constrains `A<T> < C`
    try self.searchHOF(typec, config, storage, allocator);

    if (storage.count() == 1) { // In case of insearting Variance = invariant, so only one result should be
        var it = storage.keyIterator();
        var middle = it.next().?.*.genericFollowing();
        middle.kind = Following.Kind.generic;
    }
}

pub fn searchFunction(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("Searching function {s}\n", .{next.ty});
    const from = next.ty.function.from;
    const to = next.ty.function.to;

    const fInConfig = .{
        .variance = config.variance.x(defaultVariances.functionIn),
        .insert = config.insert,
    };

    var continuations = AutoHashSet(*TypeNode).init(allocator);
    switch (from.ty.*) {
        .nominative => try self.searchNominative(from, fInConfig, &continuations, allocator),
        .function => try self.searchHOF(from, fInConfig, &continuations, allocator),
        .list => try self.searchList(from, fInConfig, &continuations, allocator),
    }

    // TODO: it's not true that it always nominative
    var followingKind = Following.Kind.arrow;
    switch (to.ty.*) {
        .nominative => {
            if (to.ty.nominative.hadGeneric) {
                followingKind = Following.Kind.generic;
            }
        },
        else => {},
    }

    const fOutConfig = .{
        .variance = config.variance.x(defaultVariances.functionOut),
        .insert = config.insert,
    };

    var continuationsIt = continuations.keyIterator();
    while (continuationsIt.next()) |continuation| {
        const following = try continuation.*.getFollowing(null, followingKind, allocator); // TODO: check null in following
        try following.to.searchWithVariance(to, fOutConfig, storage, allocator);
    }
}

pub fn searchList(
    self: *Node,
    next: *TypeC,
    config: SearchConfig,
    storage: *AutoHashSet(*TypeNode),
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("searchList {s} {}\n", .{ next.ty, variance });
    if (!next.ty.list.ordered) {
        // Order agnostic lists like OOP function parameters should be ordered before

        // NOTE: this code can be reached in case of nominative parametrized with function type
        // return EngineError.NotYetSupported;
    }
    const followingOfOpening = try self.opening.getFollowing(null, Following.Kind.fake, allocator);
    followingOfOpening.kind = Following.Kind.fake;

    const listConfig = .{
        .variance = config.variance.x(defaultVariances.tupleVariance),
        .insert = config.insert,
    };

    var currentNodes = AutoHashSet(*Node).init(allocator);
    try currentNodes.put(followingOfOpening.to, {});
    var prevTypeNodes = AutoHashSet(*TypeNode).init(allocator);
    for (next.ty.list.list.items) |nextType| {
        prevTypeNodes = AutoHashSet(*TypeNode).init(allocator);

        var currentNodesIt = currentNodes.keyIterator();
        while (currentNodesIt.next()) |currentNode| {
            switch (nextType.ty.*) {
                .function => try currentNode.*.searchHOF(nextType, listConfig, &prevTypeNodes, allocator),
                else => try currentNode.*.searchWithVariance(nextType, listConfig, &prevTypeNodes, allocator),
            }
        }

        // TODO: free!!!
        currentNodes = AutoHashSet(*Node).init(allocator);

        var prevTypeNodesIt = prevTypeNodes.keyIterator();
        while (prevTypeNodesIt.next()) |prevTypeNode| {
            // По идее тут могут встретиться ноды по которым дальше никак нельзя будет походить,
            // поэтому нужно добавить фильтр TODO:
            // Это к вопросу о том что не нужно добавлять в дерево вершины, которые заведомо никуда не ведут!!!
            const node = (try prevTypeNode.*.getFollowing(null, Following.Kind.comma, allocator)).to; // TODO: check backlink
            try currentNodes.put(node, {});
        }
    }

    // in case of adding empty tuple
    if (prevTypeNodes.count() == 0) {
        // just return previous opening parenthesis
        try prevTypeNodes.put(followingOfOpening.to.by, {});
    }

    var prevTypeNodesIt = prevTypeNodes.keyIterator();
    while (prevTypeNodesIt.next()) |prevTypeNode| {
        const followingToClosing = try prevTypeNode.*.getFollowing(null, Following.Kind.fake, allocator);
        followingToClosing.kind = Following.Kind.fake;
        const fclose = followingToClosing.to.closing;
        try storage.put(fclose, {});
    }
}

pub fn searchHOF(self: *Node, nextType: *TypeC, config: SearchConfig, storage: *AutoHashSet(*TypeNode), allocator: Allocator) EngineError!void {
    const followingOfOpening = try self.opening.getFollowing(null, Following.Kind.fake, allocator);

    var fends = AutoHashSet(*TypeNode).init(allocator);
    defer fends.deinit();
    try followingOfOpening.to.searchWithVariance(nextType, config, &fends, allocator);

    var fendsIt = fends.keyIterator();
    while (fendsIt.next()) |fend| {
        const followingToClosing = try fend.*.getFollowing(null, Following.Kind.fake, allocator);
        const fclosed: *TypeNode = followingToClosing.to.closing;

        try storage.put(fclosed, {});
    }
}

pub fn extractAllDecls(self: *Node, storage: *AutoHashSet(*Declaration)) Allocator.Error!void {
    for (self.endings.items) |ending| {
        try storage.put(ending, {});
    }

    try self.universal.extractAllDecls(storage);
    try self.opening.extractAllDecls(storage);
    try self.closing.extractAllDecls(storage);
}
