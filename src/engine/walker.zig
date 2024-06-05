const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const subtyping = @import("subtyping.zig");
const tree = @import("tree.zig");
const queryParser = @import("../query_parser.zig");

const Node = @import("Node.zig");
const SearchConfig = @import("Node.zig").SearchConfig;
const TypeNode = @import("TypeNode.zig");
const Cache = @import("cache.zig").Cache;
const EngineError = @import("error.zig").EngineError;
const AutoHashSet = utils.AutoHashSet;
const Variance = @import("variance.zig").Variance;

/// Get or insert TypeNode in cache semantically identical to given.
/// Given TypeNode must represent end of type (closing bracket in case of nominative with generic).
/// Do force insert if type is not yet exists.
//
// Current implementation don't use parallel tree and cache traversal,
// for now it dump type into string and insert in cache((( (Main issue is about handling syntetic)
pub fn mirrorFromTreeToCache(typeLastNodeInTree: *TypeNode, allocator: Allocator) EngineError!?*TypeNode {
    // std.debug.print("mirrorFromTreeToCache='{s}' '{s}'\n", .{
    //     try typeLastNodeInTree.stringPath(allocator),
    //     try typeLastNodeInTree.of.labelName(allocator),
    // });
    const cache = tree.current.cache;

    var tyStr = (try utils.typeToString(typeLastNodeInTree, allocator, true)).str;
    if (std.mem.count(u8, tyStr, "&") > 0) {
        tyStr = try std.fmt.allocPrint(allocator, "T where T < {s}", .{tyStr});
        std.debug.print("Updated type: {s}\n", .{tyStr});
    }
    const query = try queryParser.parseQuery(allocator, tyStr);

    // TODO: it's not really efficient
    var searchConfig = SearchConfig{ .variance = Variance.invariant, .insert = false };
    if (try cache.head.search(query.ty, searchConfig, allocator)) |leaf| {
        return leaf;
    } else {
        searchConfig.insert = true;
        const leaf = try cache.head.search(query.ty, searchConfig, allocator);
        try Cache.setParentsTo(leaf.?);
        return leaf;
    }

    // const nodeStartWith = getStartOfTypeEndsIn(typeLastNodeInTree);

    // return (try parallelWalk(
    //     nodeStartWith,
    //     cache.head,
    //     typeLastNodeInTree,
    //     true,
    //     Cache.setParentsTo,
    //     allocator,
    // )) orelse std.debug.panic("mirrorFromTreeToCache parallelWalk return null\n", .{});
}

// NOTE:
// // 1) `setParents` is not enough.
// // 2) Inserting is redundant.
// // 3) Fast detecting already inserted syntetic is not clear.
// fn mirrorFromCacheToTree(typeLastNodeInCache: *TypeNode, startInTree: *Node, allocator: Allocator) EngineError!*TypeNode {
//     const cache = tree.current.cache;

//     return parallelWalk(
//         cache.head,
//         startInTree,
//         typeLastNodeInCache,
//         false,
//         Node.setParentsTo,
//         allocator,
//     );
// }

fn getStartOfTypeEndsIn(end: *TypeNode) *Node {
    switch (end.kind) {
        .closing => {
            const opening = utils.getOpenParenthesis(end);
            return opening.of.by.of; // previous node to node that contains opening
        },
        .nominative => return end.of, // TODO: what should be returned in case of end of function or tuple?
        // if functions or tuple is not wrapped in parenthesis it's a bit harder to distinguish.
        // Currently eager strategy is used.
        else => {
            std.debug.panic("`getStartOfTypeEndsIn` called with kind '{}'\n", .{end.kind});
        },
    }
}

// /// Do parallel walk between X and Y tree.
// /// How `xStart` relates to `xEnd`, `yStart` relates to `yEnd`.
// /// Returns yEnd.
// /// If `forceInsert` then creates a path even if it doesn't exist yet.
// /// `setParentsTo` - function that sets parents to TypeNode from Y tree.
// fn parallelWalk(
//     xStart: *Node,
//     yStart: *Node,
//     xEnd: *TypeNode,
//     forceInsert: bool,
//     comptime setParentsTo: fn (child: *TypeNode) EngineError!void,
//     allocator: Allocator,
// ) EngineError!?*TypeNode {
//     std.debug.print("parallelWalk: x='{s}', y='{s}', X='{s}'\n", .{
//         try xStart.labelName(allocator),
//         try yStart.labelName(allocator),
//         try xEnd.name(allocator),
//     });

//     var node: *Node = undefined;
//     if (xEnd.of == xStart) { // xEnd is TypeNode of Node xStart
//         node = yStart;
//     } else {
//         if (try parallelWalk(
//             xStart,
//             yStart,
//             xEnd.of.by,
//             forceInsert,
//             setParentsTo,
//             allocator,
//         )) |node_| {
//             node = node_;
//         } else if (!forceInsert) {
//             return null;
//         } else {
//             std.debug.panic("Bad parallel walk: forceInsert='{}'", .{forceInsert});
//         }
//     }

//     // TODO: consider forceInput=false
//     // const yEndOf = (try prev.getFollowing(null, xFollowing.kind, allocator)).to; // TODO: backlink

//     // return yEnd
//     switch (xEnd.kind) {
//         .universal => return node.universal,
//         .opening => return node.opening,
//         .closing => return node.closing,
//         .nominative, .gnominative => {
//             const name = if (xEnd.kind == TypeNode.Kind.nominative) xEnd.kind.nominative else xEnd.kind.gnominative;

//             if (node.named.get(name)) |existing| {
//                 return existing;
//             } else if (forceInsert) {
//                 // TODO: is't okay to reuse kind? (Probably not, because they are in different nodes)
//                 const yEnd = try TypeNode.init(allocator, xEnd.kind, node);

//                 try node.named.put(name, yEnd);
//                 try setParentsTo(yEnd);

//                 return yEnd;
//             } else {
//                 return null;
//             }
//         },
//         .syntetic => {
//             std.debug.panic("Not yet implemented: can't map syntetic {s} from cache to tree\n", .{try xEnd.name(allocator)});
//             // var constraintsX = try subtyping.getMinorantOfNominativeUpperBounds(xEnd, allocator);

//             // return try subtyping.solveConstraintsDefinedPosition(yEndOf, &constraints, allocator);
//         },
//     }
// }

// /// The function determines ansectors of type from cache that presented in tree.
// /// In case there is type belongs to `node` in tree that is isomorphic to `parentInCache`
// /// it will be returned. In other cases it returns closest anсestors.
// pub fn setAncestorsOfTypeFromCachePresentedInTree(
//     childInTree: *TypeNode,
//     parentInCache: *TypeNode,
//     allocator: Allocator,
// ) EngineError!void {
//     const startInTree = getStartOfTypeEndsIn(childInTree);

//     if (mirrorFromCacheToTree(parentInCache, startInTree)) |parentInTree| {
//         try parentInTree.*.setAsParentTo(childInTree);
//     } else {
//         var it = parentInCache.parents.keyIterator();
//         while (it.next()) |next| {
//             try setAncestorsOfTypeFromCachePresentedInTree(childInTree, next.*, allocator);
//         }
//     }
// }

// pub fn setDescendantsOfTypeFromCachePresentedInTree(
//     parentInTree: *TypeNode,
//     childInCache: *TypeNode,
//     allocator: Allocator,
// ) EngineError!void {
//     const startInTree = getStartOfTypeEndsIn(parentInTree);

//     if (mirrorFromCacheToTree(childInCache, startInTree)) |childInTree| {
//         try parentInTree.setAsParentTo(childInTree.*);
//     } else {
//         var it = childInCache.childs.keyIterator();
//         while (it.next()) |next| {
//             try setDescendantsOfTypeFromCachePresentedInTree(parentInTree, next.*, allocator);
//         }
//     }
// }
