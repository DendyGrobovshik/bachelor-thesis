const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const EngineError = @import("error.zig").EngineError;
const Declaration = @import("tree.zig").Declaration;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const Type = @import("../query.zig").Type;
const TypeC = @import("../query.zig").TypeC;
const Following = @import("following.zig").Following;
const main = @import("../main.zig");

fn replaceWith(allocator: Allocator, str: []const u8, what: []const u8, with: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);

    var it = std.mem.splitSequence(u8, str, what);

    var skipFirst = true;
    var i: u8 = 0;
    while (it.next()) |next| {
        if (skipFirst) {
            skipFirst = false;
        } else {
            try result.appendSlice(with);
        }
        try result.appendSlice(next);
        // try result.append(i + 48);
        i += 1;
    }

    return result.items;
}

// TODO: goddamn, must be fixed
pub fn fixName(allocator: Allocator, name: []const u8, trimBegin: bool) ![]const u8 {
    var next: []const u8 = name;
    // std.debug.print("fix name: '{s}'\n", .{name});

    next = try replaceWith(allocator, next, "functionarrow322", " -> ");
    next = try replaceWith(allocator, next, "opening322", "(");
    next = try replaceWith(allocator, next, "closing322", ")");
    next = try replaceWith(allocator, next, "leftangle322", "<");
    next = try replaceWith(allocator, next, "rightangle322", ">");
    next = try replaceWith(allocator, next, "( -> ", "(");
    next = try replaceWith(allocator, next, " -> )", ")");
    // next = try replaceWith(allocator, next, "syntetic", "?");

    if (trimBegin and next.len > 3) {
        return next[3..];
    } else {
        return next;
    }
}

pub fn fixName2(allocator: Allocator, name: std.ArrayList(u8)) EngineError!std.ArrayList(u8) {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice(try fixName(allocator, name.items, true));

    return result;
}

pub fn preprocessDeclaration(allocator: Allocator, decl: Declaration) EngineError!Declaration {
    const ty: *Type = try allocator.create(Type);
    ty.* = decl.type;

    return .{ .type = (try recursiveTypeProcessor(allocator, ty)).*, .name = decl.name };
}

pub fn recursiveTypeProcessor(allocator: Allocator, ty: *Type) !*Type {
    std.debug.print("recursive type processor: {s}\n", .{ty});
    switch (ty.*) {
        .nominative => {
            if (ty.nominative.generic) |genericList| {
                // TODO: support generic argument with several types
                const generic = genericList.list.list.items[0];

                var resTy = try allocator.create(Type);
                resTy.function = .{ .from = generic, .to = ty };
                return resTy;
            } else {
                return ty;
            }
        },
        .function => {
            var resTy = try allocator.create(Type);
            resTy.function = .{
                .from = try recursiveTypeProcessor(allocator, ty.function.from),
                .to = try recursiveTypeProcessor(allocator, ty.function.to),
                .directly = ty.function.directly,
                .braced = ty.function.braced,
            };
            return resTy;
        },
        .list => return EngineError.NotYetSupported,
    }
}

pub fn endsWithRightAngle(str: []const u8) bool {
    if (str.len > 13) {
        std.debug.print("GG {s}\n", .{str});
        if (std.mem.eql(u8, str[str.len - 13 ..], "rightangle322")) {
            std.debug.print("WP\n", .{});
            return true;
        }
    }

    return false;
}

pub fn followingTo(node: *Node) *Following {
    for (node.by.followings.items) |following| {
        if (following.to == node) {
            return following;
        }
    }

    unreachable;
}

pub fn trimRightArrow(str: []const u8) []const u8 {
    if (str.len >= 4 and std.mem.eql(u8, str[str.len - 4 ..], " -> ")) {
        return str[0 .. str.len - 4];
    }

    return str;
}

pub fn simplifyName(name: []const u8, allocator: Allocator) ![]const u8 {
    if (std.mem.count(u8, name, ".") > 0) {
        return try replaceWith(allocator, name, ".", "dot");
    }

    if (std.mem.count(u8, name, "Node") > 0) {
        return try replaceWith(allocator, name, "Node", "NodeHack");
    }

    return name;
}
// const Shuffle = std.ArrayList(Type);
// // takes List type and return list of all its shuffles
// fn reshufle(_: Type, _: Allocator) !std.ArrayList(Shuffle) {
//     unreachable;
//     // TODO:
// }

// fn funcFromShuffle(_: Shuffle) Type {
//     unreachable;
//     // TODO:
// }

// pub fn unwrapType(ty: Type, allocator: Allocator) !std.ArrayList(Type) {
//     var canditates = try std.ArrayList(Type).init(allocator);

//     switch (ty) {
//         .list => {
//             for (reshuffle(ty, allocator)) |shuffle| {
//                 try candidates.append(funcFromShuffle(shuffle));
//             }
//         },
//         .function => {
//             const fromCandidates = try unwrapType(ty.function.from, allocator);
//             const toCandidates = try unwrapType(ty.function.to, allocator);

//             for (fromCandidates) |fromCantidat| {
//                 for (toCandidates) |toCandidate| {
//                     const functionCandidate = .function{
//                         .from = fromCantidat,
//                         .to = toCandidate,
//                         .directly = ty.function.directly,
//                         .braced = ty.function.braced,
//                     };

//                     try candidates.append(functionCandidate);
//                 }
//             }
//         },
//         .nominative => {
//             if (ty.nominative.generic) |generic| {
//                 const variant = try unwrapType(generic);
//                 for (variants) |variant| {
//                     const canditate = .nominative{
//                         .name = ty.nominative.name,
//                         .generic = candidate,
//                     };

//                     try candidates.append(candidate);
//                 }
//             }
//         },
//     }

//     return candidates;
// }

pub fn getBacklinkFollowingId(node: *Node) usize {
    var result: usize = 0;

    if (node.by) |of| {
        for (of.followings.items, 0..) |following, i| {
            if (following.to == node) {
                result = i;
            }
        }
    }

    return result;
}

pub fn getBacklink(ty: *TypeC) EngineError!?*TypeNode {
    const lastType = try getLastNonCompisiteType(ty);

    switch (lastType.ty.*) {
        .nominative => return lastType.ty.nominative.typeNode,
        .list => return null, // TODO: idk what should be here
        else => return EngineError.NotYetSupported,
    }
}

pub fn getLastNonCompisiteType(ty: *TypeC) EngineError!*TypeC {
    switch (ty.ty.*) {
        .function => return getLastNonCompisiteType(ty.ty.function.to),
        .nominative => {
            // т.к. номинатив раскрывается в функцию
            // и номинатив оказывается на выходной позиции, то вернуть нужно именно его

            return ty;
        },
        else => return ty.ty.list.list.getLast(),
    }
}

/// Takes typeNode of closing parenthesis
/// Returns mathcing open parenthesis
pub fn getOpenParenthesis(typeNode: *TypeNode) *TypeNode {
    var currentNode = typeNode;

    while (!currentNode.isOpening()) {
        if (currentNode.of.by.isClosing()) {
            const innerPairOpening = getOpenParenthesis(currentNode.of.by);
            currentNode = innerPairOpening.of.by; // node before inner opening parenthesis
        } else {
            currentNode = currentNode.of.by;
        }
    }

    return currentNode;
}

/// if type is function and input parameter is order agnostic list then turn it into ordered
/// do sort inplace
/// order by lexicographic of string representation of types
pub fn orderTypeParameters(ty: *TypeC, allocator: Allocator) *TypeC {
    // skip all other cases
    switch (ty.ty.*) {
        .function => {
            switch (ty.ty.function.from.ty.*) {
                .list => {
                    const list = ty.ty.function.from.ty.list;
                    if (list.ordered) {
                        return ty;
                    }
                },
                else => return ty,
            }
        },
        else => return ty,
    }

    const list = ty.ty.function.from.ty.list;
    // std.debug.print("Ordering: {s}\n", .{list});

    std.mem.sort(*TypeC, list.list.items, allocator, typecComparator);
    ty.ty.function.from.ty.list.ordered = true;
    // std.debug.print("Ordered: {s}\n", .{list});

    return ty;
}

fn typecComparator(allocator: Allocator, lhs: *TypeC, rhs: *TypeC) bool {
    const leftStr = std.fmt.allocPrint(allocator, "{s}", .{lhs}) catch unreachable;
    const rightStr = std.fmt.allocPrint(allocator, "{s}", .{rhs}) catch unreachable;

    // std.debug.print("COMPARING '{s}' and '{s}'\n", .{ lhs, rhs });

    return leftLess(leftStr, rightStr);
}

fn leftLess(left: []const u8, right: []const u8) bool {
    const minLength = if (left.len < right.len) left.len else right.len;

    for (0..minLength) |i| {
        if (left[i] == right[i]) {
            continue;
        } else if (left[i] < right[i]) {
            return true;
        } else {
            return false;
        }
    }

    // NOTE: `<=` is not valid here
    return left.len < right.len;
}
