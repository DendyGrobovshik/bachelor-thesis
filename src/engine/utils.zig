const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Declaration = @import("tree.zig").Declaration;
const Node = @import("node.zig").Node;
const TypeNode = @import("typeNode.zig").TypeNode;
const Type = @import("../query.zig").Type;
const TypeC = @import("../query.zig").TypeC;
const TreeOperationError = @import("tree.zig").TreeOperationError;

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
    next = try replaceWith(allocator, next, "functionopening322", "(");
    next = try replaceWith(allocator, next, "functionclosing322", ")");
    next = try replaceWith(allocator, next, "( -> ", "(");
    next = try replaceWith(allocator, next, " -> )", ")");
    // next = try replaceWith(allocator, next, "syntetic", "?");

    if (trimBegin and next.len > 3) {
        return next[3..];
    } else {
        return next;
    }
}

pub fn fixName2(allocator: Allocator, name: std.ArrayList(u8)) TreeOperationError!std.ArrayList(u8) {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice(try fixName(allocator, name.items, true));

    return result;
}

pub fn preprocessDeclaration(allocator: Allocator, decl: Declaration) TreeOperationError!Declaration {
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
        .list => return TreeOperationError.NotYetSupported,
    }
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

    if (node.of) |of| {
        for (of.followings.items, 0..) |following, i| {
            if (following.to == node) {
                result = i;
            }
        }
    }

    return result;
}

pub fn getBacklink(ty: *TypeC) Node.NodeError!?*TypeNode {
    const lastType = try getLastNonCompisiteType(ty);

    switch (lastType.ty.*) {
        .nominative => return lastType.ty.nominative.typeNode,
        else => return Node.NodeError.NotYetSupported,
    }
}

pub fn getLastNonCompisiteType(ty: *TypeC) Node.NodeError!*TypeC {
    switch (ty.ty.*) {
        .function => return getLastNonCompisiteType(ty.ty.function.to),
        .nominative => {
            // т.к. номинатив раскрывается в функцию
            // и номинатив оказывается на выходной позиции, то вернуть нужно именно его

            return ty;
        },
        else => return Node.NodeError.NotYetSupported,
    }
}
