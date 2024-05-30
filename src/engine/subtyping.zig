const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const tree = @import("tree.zig");

const AutoHashSet = utils.AutoHashSet;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const EngineError = @import("error.zig").EngineError;
const Server = @import("../driver/server.zig").Server;

/// Use it for checking subtype relation on graph.
/// It checks that `what` in poset upper bound set of `of` TypeNode.
pub fn isInUpperBounds(what: *TypeNode, of: *TypeNode) bool {
    if (what == of) {
        return true;
    }

    var it = of.parents.keyIterator();
    while (it.next()) |ofParent| {
        if (isInUpperBounds(what, ofParent.*)) {
            return true;
        }
    }

    return false;
}

/// Inserting nominative in subtyping graph.
/// Set all the childs and parents to `it`.
pub fn insertNominative(
    it: *TypeNode,
    to: *Node,
    comptime isSubtype: fn (child: *TypeNode, parent: *TypeNode) EngineError!bool,
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("insertNominative: {s}\n", .{try it.name(allocator)});
    var upperBounds = AutoHashSet(*TypeNode).init(allocator);
    try upperBounds.put(to.universal, {});

    var incomparable = AutoHashSet(*TypeNode).init(allocator);

    var minorantsOfUpperBounds = AutoHashSet(*TypeNode).init(allocator);
    while (upperBounds.count() > 0) {
        var newUpperBounds = AutoHashSet(*TypeNode).init(allocator);

        var upperBoundsIt = upperBounds.keyIterator();
        while (upperBoundsIt.next()) |upperBound| {
            var pushed = false;

            var upperBoundChildsIt = upperBound.*.childs.keyIterator();
            while (upperBoundChildsIt.next()) |mbChild| {
                if (try isSubtype(it, mbChild.*)) {
                    pushed = true;
                    try newUpperBounds.put(mbChild.*, {});
                } else {
                    try incomparable.put(mbChild.*, {});
                }
            }

            if (!pushed) {
                try minorantsOfUpperBounds.put(upperBound.*, {});
            }
        }

        upperBounds = newUpperBounds; // TODO: free
    }

    if (minorantsOfUpperBounds.count() == 1) {
        var minorantsOfUpperBoundsIt = minorantsOfUpperBounds.keyIterator();
        const parent = minorantsOfUpperBoundsIt.next().?.*;
        try parent.setAsParentTo(it);
    } else {
        const synteticParent = try solveConstraintsDefinedPosition(to, &minorantsOfUpperBounds, allocator);
        try synteticParent.setAsParentTo(it);
    }

    // Some successors of not comparable TypeNode can be child of currently inserted.
    // NOTE: it's slow operation (checking all incomparable recursivelly is terrible)
    // It can be easily optimized if childs of nominative is known.
    try setAsParentToSuccessorsOfIncomparableIfNeeded(it, &incomparable, isSubtype, allocator); // TODO: free
}

pub fn setAsParentToSuccessorsOfIncomparableIfNeeded(
    parent: *TypeNode,
    incomparable_: *AutoHashSet(*TypeNode),
    isSubtype: fn (child: *TypeNode, parent: *TypeNode) EngineError!bool,
    allocator: Allocator,
) EngineError!void {
    // std.debug.print("setAsParentToSuccessorsOfIncomparableIfNeeded {s} {}\n", .{
    //     try parent.name(allocator),
    //     incomparable_.count(),
    // });

    var incomparable = try incomparable_.clone();

    while (incomparable.count() != 0) {
        var newIncomparable = AutoHashSet(*TypeNode).init(allocator);

        var incomparableIt = incomparable.keyIterator();
        while (incomparableIt.next()) |next| {
            if (try isSubtype(next.*, parent)) {
                if (next.*.parents.count() == 1 and next.*.parents.contains(next.*.of.universal)) {
                    next.*.of.universal.removeChild(next.*);
                }
                try parent.setAsParentTo(next.*);
            } else {
                var nextChildsIt = next.*.childs.keyIterator();
                while (nextChildsIt.next()) |nextChild| {
                    try newIncomparable.put(nextChild.*, {});
                }
            }
        }

        incomparable = newIncomparable;
    }
}

pub fn solveConstraintsDefinedPosition(node: *Node, constraints: *AutoHashSet(*TypeNode), allocator: Allocator) EngineError!*TypeNode {
    // std.debug.print("solveConstraintsDefinedPosition {}\n", .{constraints.count()});

    if (constraints.count() == 0) {
        return node.universal;
    }

    var minorants = AutoHashSet(*TypeNode).init(allocator);

    var currents = try constraints.clone();

    while (currents.count() > 0) {
        var newCurrents = AutoHashSet(*TypeNode).init(allocator);

        var currentsIt = currents.keyIterator();
        while (currentsIt.next()) |current| {
            var changed = false;

            var currentChildsIt = current.*.childs.keyIterator();
            while (currentChildsIt.next()) |currentChild| {
                if (currentChild.*.kind != TypeNode.Kind.syntetic) {
                    continue;
                }

                var common = try getCommonMinorantsWithTypeNode(constraints, currentChild.*, allocator);
                var parentCommon = try getCommonMinorantsWithTypeNode(constraints, current.*, allocator);
                if (common.count() > 1 and common.count() > parentCommon.count()) {
                    const middle = try getOrInsertSyntetic(current.*, currentChild.*, &common, allocator);
                    try newCurrents.put(middle, {});
                    changed = true;
                }
            }

            if (!changed) {
                try minorants.put(current.*, {});
            }
        }

        currents = newCurrents;
    }

    if (minorants.count() == 1) {
        var it = minorants.keyIterator();
        return it.next().?.*;
    }

    const newUpperBound = try TypeNode.init(allocator, TypeNode.Kind.syntetic, node);
    try node.syntetics.append(newUpperBound);

    var it = minorants.keyIterator();
    while (it.next()) |parent| {
        try parent.*.setAsParentTo(newUpperBound);
    }

    return newUpperBound;
}

/// Get or insert syntetic between `parent` and `child` with `middleMinorants` nominative upper bound minorants.
//
// In case of inserting middle - child has other minorants and have to be moved in another syntetic
fn getOrInsertSyntetic(parent: *TypeNode, child: *TypeNode, middleMinorants: *AutoHashSet(*TypeNode), allocator: Allocator) EngineError!*TypeNode {
    var childMinorants = try getMinorantOfNominativeUpperBounds(child, allocator);

    if (childMinorants.count() == middleMinorants.count()) {
        return child;
    }

    const middle = try TypeNode.init(allocator, TypeNode.Kind.syntetic, parent.of);
    try parent.of.syntetics.append(middle);

    const rest = try TypeNode.init(allocator, TypeNode.Kind.syntetic, parent.of);
    try parent.of.syntetics.append(rest);

    {
        var it = child.parents.keyIterator();
        while (it.next()) |next| {
            var nextMinorants = try getMinorantOfNominativeUpperBounds(next.*, allocator);
            if (utils.isSubset(*TypeNode, &nextMinorants, middleMinorants)) {
                try next.*.setAsParentTo(middle);
            } else {
                try next.*.setAsParentTo(rest);
            }
        }
    }

    while (child.parents.count() > 0) {
        var it = child.parents.keyIterator();
        const next = it.next().?.*;
        next.removeChild(child);
    }

    try middle.setAsParentTo(child);
    try rest.setAsParentTo(child);

    return middle;
}

// get common minorants of nominative upper bounds of TypeNodes
fn getCommonMinorantsWithTypeNode(xMinorants: *AutoHashSet(*TypeNode), y: *TypeNode, allocator: Allocator) Allocator.Error!AutoHashSet(*TypeNode) {
    var yMinorants = try getMinorantOfNominativeUpperBounds(y, allocator);
    defer yMinorants.deinit();

    return try utils.setIntersection(*TypeNode, xMinorants, &yMinorants, allocator);
}

pub fn getMinorantOfNominativeUpperBounds(typeNode: *TypeNode, allocator: Allocator) Allocator.Error!AutoHashSet(*TypeNode) {
    var result = AutoHashSet(*TypeNode).init(allocator);
    try result.put(typeNode, {});

    out: while (true) {
        var it = result.keyIterator();
        while (it.next()) |x| {
            if (x.*.kind == TypeNode.Kind.syntetic) {
                var xIt = x.*.parents.keyIterator();
                while (xIt.next()) |next| {
                    try result.put(next.*, {});
                }
                _ = result.remove(x.*);
                continue :out;
            }
        }
        break;
    }

    return result;
}
