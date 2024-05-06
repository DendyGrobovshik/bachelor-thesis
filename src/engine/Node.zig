const Node = @import("Node.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const LOG = @import("config").logp;

const EngineError = @import("error.zig").EngineError;
const TypeNode = @import("TypeNode.zig");
const Declaration = @import("tree.zig").Declaration;
const utils = @import("utils.zig");
const Function = @import("../query.zig").Function;
const Type = @import("../query.zig").Type;
const TypeC = @import("../query.zig").TypeC;
const Constraint = @import("../query.zig").Constraint;
const Following = @import("following.zig").Following;
const main = @import("../main.zig");

// NOTE: all the decls become public
pub usingnamespace @import("Node_printing.zig");

named: std.StringHashMap(*TypeNode),
syntetics: std.ArrayList(*TypeNode),

universal: *TypeNode,
opening: *TypeNode,
closing: *TypeNode,

endings: std.ArrayList(*Declaration),
by: *TypeNode,

pub fn init(allocator: Allocator, by: *TypeNode) EngineError!*Node {
    const named = std.StringHashMap(*TypeNode).init(allocator);
    const syntetics = std.ArrayList(*TypeNode).init(allocator);

    const endings = std.ArrayList(*Declaration).init(allocator);

    const self = try allocator.create(Node);

    const universal = try TypeNode.init(allocator, TypeNode.Kind.universal, self);
    const opening = try TypeNode.init(allocator, TypeNode.Kind.opening, self);
    const closing = try TypeNode.init(allocator, TypeNode.Kind.closing, self);
    try universal.setAsParentTo(opening);
    try universal.setAsParentTo(closing);

    self.* = .{
        .named = named,
        .syntetics = syntetics,
        .universal = universal,
        .opening = opening,
        .closing = closing,
        .endings = endings,
        .by = by,
    };

    return self;
}

// do exact search or insert if no present
pub fn search(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    switch (next.ty.*) {
        .nominative => return try self.searchNominative(next, allocator),
        .function => return try self.searchFunction(next, allocator),
        .list => return try self.searchList(next, allocator),
    }
}

pub fn searchNominative(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    if (next.ty.nominative.generic) |_| {
        return try self.searchNominativeWithGeneric(next, allocator);
    }

    if (!next.ty.nominative.isGeneric()) {
        return self.searchRealNominative(next, allocator);
    } else {
        return self.searchGeneric(next, allocator);
    }
}

pub fn searchRealNominative(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    if (self.named.get(next.ty.nominative.name)) |alreadyInserted| {
        return alreadyInserted;
    }
    const name = try utils.simplifyName(next.ty.nominative.name, allocator);
    var newTypeNode: *TypeNode = undefined;
    if (next.ty.nominative.hadGeneric) {
        newTypeNode = try TypeNode.init(allocator, .{ .gnominative = name }, self);
    } else {
        newTypeNode = try TypeNode.init(allocator, .{ .nominative = name }, self);
    }

    try self.named.put(name, newTypeNode);

    try solveNominativePosition(self.universal, newTypeNode);

    return newTypeNode;
}

pub fn searchGeneric(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    var parents = std.ArrayList(*TypeNode).init(allocator);

    // generic are only constraint defined, and it requires another inserting algorithm
    for (next.constraints.items) |constraint| {
        if (LOG) {
            std.debug.print("Inserting constraint {s} < {s}\n", .{ next.ty.*, constraint });
        }

        for (constraint.superTypes.items) |superType| {
            const constraintTypeNode = try self.search(superType, allocator);
            try parents.append(constraintTypeNode);
        }
    }

    if (parents.items.len == 0) {
        try parents.append(self.universal);
    }

    const result = try solvePosition(self, parents, allocator);

    if (next.ty.nominative.typeNode) |backlink| {
        const following = try allocator.create(Following);
        following.to = try Node.init(allocator, result);
        following.backlink = backlink;
        try result.followings.append(following);
    } else {
        next.ty.nominative.typeNode = result;
    }

    return result;
}

// Находит позицию джененрика в графе подстановки
// Все позиции дженериков(даже universal) являются синтетическими(AA??)
//
// Констрейнты определяют TypeNode меньше которых должна быть вставляемая(искомая)
// Они могут быть как функциональными или соотетсвющие именам(но не составными)
//
// TODO: support subtype checking for functions
pub fn solvePosition(self: *Node, parents_: std.ArrayList(*TypeNode), allocator: Allocator) EngineError!*TypeNode {
    var parents = std.AutoHashMap(*TypeNode, void).init(allocator);
    for (parents_.items) |parent| {
        try parents.put(parent, {});
    }

    // // TODO: remove debug printing
    // var it = parents.keyIterator();
    // while (it.next()) |parent| {
    //     std.debug.print("Next initial parent: {s}\n", .{parent.*.of});
    // }

    // if any 2 of them have common child replace with it
    // (The child must be syntetic! Or synteric should be inserted betwen parents and him)
    var changed = true;
    while (changed) {
        if (parents.count() == 1) {
            break;
        }

        changed = false;

        var syntetic_: ?*TypeNode = null;

        var it1 = parents.keyIterator();
        outer: while (it1.next()) |x| {
            var it2 = parents.keyIterator();
            while (it2.next()) |y| {
                if (x != y) {
                    find_next_common_child: for (x.*.childs.items, 0..) |xChild, xi| {
                        for (y.*.childs.items, 0..) |yChild, yi| {
                            if (xChild == yChild) { // ptr equality
                                // first common child may be not only one
                                const commonChild = xChild;
                                // std.debug.print("It's common child is {s}\n", .{commonChild.of});
                                // if common child is syntetic then no other commom childs can be
                                if (commonChild.isSyntetic()) {
                                    // std.debug.print("is syntetic\n", .{});
                                    // TODO: not ignore operation result
                                    _ = parents.remove(x.*);
                                    _ = parents.remove(y.*);
                                    try parents.put(commonChild, {});
                                    // std.debug.print("parents was replaced with syntetic and parents size now: {}\n", .{parents.count()});
                                } else {
                                    // std.debug.print("not syntetic\n", .{});
                                    // common is not syntetic, so it should be divorced from parents with syntetic

                                    // breaking current relations
                                    _ = x.*.childs.swapRemove(xi);
                                    _ = y.*.childs.swapRemove(yi);

                                    // TODO: check bug if 2 times performed same type searching
                                    var parentsRemoved: u2 = 0;
                                    remove_parents_from_child: while (true) {
                                        // std.debug.print("Removing parent from child: '{s}' with {} super\n", .{ commonChild.of, commonChild.parents.items.len });
                                        for (0..commonChild.parents.items.len) |ci| {
                                            if (commonChild.parents.items[ci] == x.*) {
                                                _ = commonChild.parents.swapRemove(ci);
                                                parentsRemoved += 1;
                                                break;
                                            } else if (commonChild.parents.items[ci] == y.*) {
                                                _ = commonChild.parents.swapRemove(ci);
                                                parentsRemoved += 1;
                                                break;
                                            }

                                            if (parentsRemoved == 2) {
                                                break :remove_parents_from_child;
                                                // break;
                                            }
                                        }

                                        if (commonChild.parents.items.len == 0) {
                                            break :remove_parents_from_child;
                                        }
                                    }

                                    // const synteticName = try std.fmt.allocPrint(allocator, "syntetic{}", .{globalSynteticId});
                                    // globalSynteticId += 1;
                                    const syntetic = syntetic_ orelse try TypeNode.init(allocator, TypeNode.Kind.syntetic, self);
                                    // syntetic.kind = Kind.syntetic;
                                    syntetic_ = syntetic;

                                    try x.*.setAsParentTo(syntetic);
                                    try y.*.setAsParentTo(syntetic);
                                    try syntetic.setAsParentTo(commonChild);

                                    // for example Array and Set are implementing Collection and Printable
                                    // so both of them should be relinked with syntetic
                                    // so other common childred should be founded
                                    break :find_next_common_child;
                                }
                                changed = true;
                                break :outer;
                            }
                        }
                    }
                }
            }
        }
    }

    if (parents.count() != 1) {
        // pure syntetic, no one reach this state yet
        // const synteticName = try std.fmt.allocPrint(allocator, "syntetic{}", .{globalSynteticId});
        // globalSynteticId += 1;
        const syntetic = try TypeNode.init(allocator, TypeNode.Kind.syntetic, self);
        // syntetic.kind = .syntetic;

        var it = parents.keyIterator();
        while (it.next()) |parent| {
            // std.debug.print("New syntetic was synthesized from: {s}\n", .{parent.*.of});
            try parent.*.setAsParentTo(syntetic);
        }

        try self.syntetics.append(syntetic);

        // std.debug.print("this syntetic supers\n", .{});
        // for (syntetic.parents.items) |super| {
        //     std.debug.print("super: {s}\n", .{super.of});
        // }

        return syntetic;
    }

    var it = parents.keyIterator();
    while (it.next()) |parent| {
        // std.debug.print("Next updated parent: {s}\n", .{parent.*.of});

        switch (parent.*.kind) {
            .syntetic => try self.syntetics.append(parent.*),
            else => {},
        }

        return parent.*;
    }

    // TODO: this is cringe code, but alternatives can lead to seagfault
    return EngineError.ShouldBeUnreachable;
}

// Даже если у номинатива есть ограничения их не нужно знать заранее,
// поскольку алгоритм его вставки состоит в проталкивании его вниз,
// то есть его ограничения будут проверяться непосредственно в ходе этой операции.
//
// Эту функцию стоит вызывать только если такого номинатива ещё нет в графе(иначе можно вернуть то что находиться в мапе types)
// TODO: предыдущее верно в случае если у типа неизменный набор ограничений
//
// Алгоритм следующий: 1) верно что для данной ноды вставляемая подставима
// Перебираются все меньшие к текущей и если находятся старшие к вставляемой,
// то связь с текущей удаляется и выставляются связи к нижестоящим
// (Если изначально передавать текущую без связи, то наоборот, если кандижатов нет, то выставляется
// связь с текущей, а иначе рекурсивно вызывается поиск с кандидатами из ниже стоящих)
// TODO: обработать случай когда нижестоящая является синтетической вершиной
// (для неё справедлив факт её можно использовать как кандидата)
pub fn solveNominativePosition(current: *TypeNode, new: *TypeNode) EngineError!void {
    var pushedBelow = false;

    for (current.childs.items) |sub| {
        if (try sub.greater(new)) {
            pushedBelow = true;
            _ = try solveNominativePosition(sub, new);
        }

        // Or if it's syntatic typeNode (constraint defined)
        // and substable for all top nodes of syntetic
        // TODO: возможно придётся расщеплять синтетику, потому что не все её топ ноды могут быть старшими к текущей
        // ??: опять же подходящие старшие будут поставлены выше текущий по другим путям
        if (sub.isSyntetic()) {
            pushedBelow = true;
            for (sub.parents.items) |subParent| {
                // std.debug.print("syn top: {s} {}\n", .{ subParent.of, subParent.greater(new) });
                if (!(try subParent.greater(new))) {
                    pushedBelow = false;
                }
            }

            if (pushedBelow) {
                _ = try solveNominativePosition(sub, new);
            }
        }
    }

    if (!pushedBelow) {
        try current.setAsParentTo(new);
    }

    // return new;
}

pub fn searchNominativeWithGeneric(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    if (LOG) {
        std.debug.print("Searching nominative with generic \n", .{});
    }
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
        .function => return EngineError.NotYetSupported,
    };

    const ty = try allocator.create(Type);
    ty.function = .{
        .from = from,
        .to = try TypeC.init(allocator, newNextType),
    };

    const typec = try TypeC.init(allocator, ty);

    // TODO: handle constrains `A<T> < C`
    const result = try self.searchHOF(typec, allocator);

    const middle = result.genericFollowing();
    middle.kind = Following.Kind.generic;

    return result;
}

pub fn searchFunction(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    if (LOG) {
        std.debug.print("Searching function {s}\n", .{next.ty});
    }
    const from = next.ty.function.from;
    const to = next.ty.function.to;

    var continuation: *TypeNode = undefined;
    switch (from.ty.*) {
        .nominative => continuation = try self.searchNominative(from, allocator),
        .function => continuation = try self.searchHOF(from, allocator),
        .list => continuation = try self.searchList(from, allocator),
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

    const following = try continuation.getFollowing(null, followingKind, allocator);
    return try (following).to.search(to, allocator); // TODO: check null in following
}

pub fn searchList(self: *Node, next: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    if (!next.ty.list.ordered) {
        return EngineError.NotYetSupported;
    }

    var current = self;
    var typeNode: *TypeNode = undefined;
    for (next.ty.list.list.items) |nextType| {
        typeNode = try current.search(nextType, allocator);

        current = (try typeNode.getFollowing(null, Following.Kind.comma, allocator)).to; // TODO: check backlink
    }

    return typeNode;
}

pub fn searchHOF(self: *Node, nextType: *TypeC, allocator: Allocator) EngineError!*TypeNode {
    const followingOfOpening = try self.opening.getFollowing(null, Following.Kind.fake, allocator);
    followingOfOpening.kind = Following.Kind.fake;
    const fend = try followingOfOpening.to.search(nextType, allocator);

    const followingToClosing = try fend.getFollowing(null, Following.Kind.fake, allocator);
    followingToClosing.kind = Following.Kind.fake;
    const fclose = followingToClosing.to.closing;

    return fclose;
}

// pub fn searchPrimitive(self: *Node, what: TypeNode.Of, allocator: Allocator) EngineError!*TypeNode {
//     if (self.named.get(what)) |typeNode| {
//         return typeNode;
//     }

//     const newTypeNode = try TypeNode.init(allocator, what);
//     const universal = self.universal;

//     try newTypeNode.parents.append(universal);
//     try universal.childs.append(newTypeNode);

//     try self.types.put(what, newTypeNode);

//     return self.types.get(what) orelse unreachable;
// }

pub fn extractAllDecls(self: *Node, allocator: Allocator) !std.ArrayList(*Declaration) {
    var result = std.ArrayList(*Declaration).init(allocator);

    try result.appendSlice(self.endings.items);
    try result.appendSlice((try self.universal.extractAllDecls(allocator)).items);

    return result;
}