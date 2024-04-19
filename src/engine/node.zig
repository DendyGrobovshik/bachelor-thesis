const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const TypeNode = @import("typeNode.zig").TypeNode;
const TypeNodeKind = @import("typeNode.zig").TypeNode.TypeNodeKind;
const Declaration = @import("tree.zig").Declaration;
const utils = @import("utils.zig");
const Function = @import("../query.zig").Function;
const Type = @import("../query.zig").Type;
const TypeC = @import("../query.zig").TypeC;
const Constraint = @import("../query.zig").Constraint;

var globalSynteticId: usize = 0;

pub const Node = struct {
    pub const NodeError = error{
        NotYetSupported,
        ShouldBeUnreachable,
    } || std.mem.Allocator.Error;

    // points to named part of substition graph
    types: std.StringHashMap(*TypeNode),
    universal: *TypeNode,
    endings: std.ArrayList(*Declaration),
    of: ?*TypeNode,

    syntetics: std.ArrayList(*TypeNode),

    pub fn init(allocator: Allocator, of: ?*TypeNode) NodeError!*Node {
        var types = std.StringHashMap(*TypeNode).init(allocator);

        const universalOf = "T";
        const universal = try TypeNode.init(allocator, universalOf);
        universal.kind = TypeNodeKind.universal;
        try types.put(universalOf, universal);

        const endings = std.ArrayList(*Declaration).init(allocator);
        const syntetics = std.ArrayList(*TypeNode).init(allocator);

        const self = try allocator.create(Node);

        self.* = .{
            .types = types,
            .universal = universal,
            .endings = endings,
            .of = of,
            .syntetics = syntetics,
        };

        universal.preceding = self;

        return self;
    }

    // do exact search or insert if no present
    pub fn search(self: *Node, next: *TypeC, allocator: Allocator) NodeError!*TypeNode {
        switch (next.ty.*) {
            .nominative => return try self.searchNominative(next, allocator),
            .function => return try self.searchFunction(next, allocator),
            .list => return NodeError.NotYetSupported,
        }
    }

    // TODO: handle constraints?
    pub fn searchNominative(self: *Node, next: *TypeC, allocator: Allocator) NodeError!*TypeNode {
        std.debug.print("Searching nominative {s}\n", .{next.ty});
        // TODO: check is it correct handles `A<T>` and `A`
        if (next.ty.nominative.generic) |_| {
            std.debug.print("before calling searchNominativeWithGeneric\n", .{});
            return try self.searchNominativeWithGeneric(next, allocator);
        }

        const typeNodeOf = next.ty.nominative.name;

        if (!next.ty.nominative.isGeneric()) {
            if (self.types.get(typeNodeOf)) |alreadyInserted| {
                return alreadyInserted;
            }

            const newTypeNode = try TypeNode.init(allocator, typeNodeOf);
            if (next.ty.nominative.hadGeneric) {
                newTypeNode.kind = TypeNodeKind.gout;
            }
            try self.types.put(typeNodeOf, newTypeNode);
            // NOTE: it's not necessary to return function result, 'newTypeNode' can be used

            const result = try solveNominativePosition(self.universal, newTypeNode);

            return result;
        }

        var parents = std.ArrayList(*TypeNode).init(allocator);

        // generic are only constraint defined, and it requires another inserting algorithm
        for (next.constraints.items) |constraint| {
            std.debug.print("Inserting constraint {s} < {s}\n", .{ next.ty.*, constraint });

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
            const following = try allocator.create(TypeNode.Following);
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
    fn solvePosition(self: *Node, parents_: std.ArrayList(*TypeNode), allocator: Allocator) NodeError!*TypeNode {
        var parents = std.AutoHashMap(*TypeNode, void).init(allocator);
        for (parents_.items) |parent| {
            try parents.put(parent, {});
        }

        // TODO: remove debug printing
        var it = parents.keyIterator();
        while (it.next()) |parent| {
            std.debug.print("Next initial parent: {s}\n", .{parent.*.of});
        }

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
                        find_next_common_child: for (x.*.sub.items, 0..) |xChild, xi| {
                            for (y.*.sub.items, 0..) |yChild, yi| {
                                if (xChild == yChild) { // ptr equality
                                    // first common child may be not only one
                                    const commonChild = xChild;
                                    std.debug.print("It's common child is {s}\n", .{commonChild.of});
                                    // if common child is syntetic then no other commom childs can be
                                    if (commonChild.isSyntetic()) {
                                        std.debug.print("is syntetic\n", .{});
                                        // TODO: not ignore operation result
                                        _ = parents.remove(x.*);
                                        _ = parents.remove(y.*);
                                        try parents.put(commonChild, {});
                                        std.debug.print("parents was replaced with syntetic and parents size now: {}\n", .{parents.count()});
                                    } else {
                                        std.debug.print("not syntetic\n", .{});
                                        // common is not syntetic, so it should be divorced from parents with syntetic

                                        // breaking current relations
                                        _ = x.*.sub.swapRemove(xi);
                                        _ = y.*.sub.swapRemove(yi);

                                        // TODO: check bug if 2 times performed same type searching
                                        var parentsRemoved: u2 = 0;
                                        remove_parents_from_child: while (true) {
                                            std.debug.print("Removing parent from child: '{s}' with {} super\n", .{ commonChild.of, commonChild.super.items.len });
                                            for (0..commonChild.super.items.len) |ci| {
                                                if (commonChild.super.items[ci] == x.*) {
                                                    _ = commonChild.super.swapRemove(ci);
                                                    parentsRemoved += 1;
                                                    break;
                                                } else if (commonChild.super.items[ci] == y.*) {
                                                    _ = commonChild.super.swapRemove(ci);
                                                    parentsRemoved += 1;
                                                    break;
                                                }

                                                if (parentsRemoved == 2) {
                                                    break :remove_parents_from_child;
                                                    // break;
                                                }
                                            }

                                            if (commonChild.super.items.len == 0) {
                                                break :remove_parents_from_child;
                                            }
                                        }

                                        const synteticName = try std.fmt.allocPrint(allocator, "syntetic{}", .{globalSynteticId});
                                        globalSynteticId += 1;
                                        const syntetic = syntetic_ orelse try TypeNode.init(allocator, synteticName);
                                        syntetic.kind = TypeNodeKind.syntetic;
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
            const synteticName = try std.fmt.allocPrint(allocator, "syntetic{}", .{globalSynteticId});
            globalSynteticId += 1;
            const syntetic = try TypeNode.init(allocator, synteticName);
            syntetic.kind = TypeNodeKind.syntetic;

            it = parents.keyIterator();
            while (it.next()) |parent| {
                std.debug.print("New syntetic was synthesized from: {s}\n", .{parent.*.of});
                try parent.*.setAsParentTo(syntetic);
            }

            try self.syntetics.append(syntetic);

            std.debug.print("this syntetic supers\n", .{});
            for (syntetic.super.items) |super| {
                std.debug.print("super: {s}\n", .{super.of});
            }

            return syntetic;
        }

        it = parents.keyIterator();
        while (it.next()) |parent| {
            std.debug.print("Next updated parent: {s}\n", .{parent.*.of});

            switch (parent.*.kind) {
                .syntetic => try self.syntetics.append(parent.*),
                else => {},
            }

            return parent.*;
        }

        // TODO: this is cringe code, but alternatives can lead to seagfault
        return NodeError.ShouldBeUnreachable;
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
    fn solveNominativePosition(current: *TypeNode, new: *TypeNode) NodeError!*TypeNode {
        var pushedBelow = false;

        for (current.sub.items) |sub| {
            if (sub.greater(new)) {
                pushedBelow = true;
                _ = try solveNominativePosition(sub, new);
            }

            // Or if it's syntatic typeNode (constraint defined)
            // and substable for all top nodes of syntetic
            // TODO: возможно придётся расщеплять синтетику, потому что не все её топ ноды могут быть старшими к текущей
            // ??: опять же подходящие старшие будут поставлены выше текущий по другим путям
            if (std.mem.eql(u8, sub.of, "?")) {
                pushedBelow = true;
                for (sub.super.items) |subParent| {
                    std.debug.print("syn top: {s} {}\n", .{ subParent.of, subParent.greater(new) });
                    if (!subParent.greater(new)) {
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

        return new;
    }

    // fn currentInfimum(x: *TypeNode, y: *TypeNode) *TypeNode {}

    fn searchNominativeWithGeneric(self: *Node, next: *TypeC, allocator: Allocator) NodeError!*TypeNode {
        std.debug.print("Searching nominative with generic \n", .{});
        const generic = next.ty.nominative.generic orelse unreachable;

        // removing generic to escape recursive loop
        const newNextType = try allocator.create(Type);
        newNextType.* = .{ .nominative = .{
            .name = next.ty.nominative.name,
            .generic = null,
            .hadGeneric = true,
        } };

        const ty = try allocator.create(Type);
        ty.function = .{
            .from = generic.ty.list.list.items[0], // TODO: support not only 1-parameter genrics
            .to = try TypeC.init(allocator, newNextType),
        };

        const typec = try TypeC.init(allocator, ty);

        // TODO: handle constrains `A<T> < C`
        return try self.searchHOF(typec, allocator);
    }

    pub fn searchFunction(self: *Node, next: *TypeC, allocator: Allocator) NodeError!*TypeNode {
        std.debug.print("Searching function {s}\n", .{next.ty});
        const from = next.ty.function.from;
        const to = next.ty.function.to;

        var continuation: *TypeNode = undefined;
        switch (from.ty.*) {
            .nominative => continuation = try self.searchNominative(from, allocator),
            .function => continuation = try self.searchHOF(from, allocator),
            .list => return NodeError.NotYetSupported,
        }

        return try (try continuation.getFollowing(null, allocator)).search(to, allocator); // TODO: check null in following
    }

    fn searchHOF(self: *Node, nextType: *TypeC, allocator: Allocator) NodeError!*TypeNode {
        // const fopen = try self.searchPrimitive(TypeNode.Of{ .fopen = {} }, allocator);
        const fopen = try self.searchPrimitive("functionopening322", allocator);
        fopen.kind = TypeNodeKind.open;

        const fend = try (try fopen.getFollowing(null, allocator)).search(nextType, allocator);

        const fclose = try (try fend.getFollowing(null, allocator)).searchPrimitive("functionclosing322", allocator);
        fclose.kind = TypeNodeKind.close;
        // const fclose = try (try fend.getFollowing(allocator)).searchPrimitive(TypeNode.Of{ .fclose = {} }, allocator);

        return fclose;
    }

    fn searchPrimitive(self: *Node, what: TypeNode.Of, allocator: Allocator) NodeError!*TypeNode {
        if (self.types.get(what)) |typeNode| {
            return typeNode;
        }

        const newTypeNode = try TypeNode.init(allocator, what);
        const universal = self.universal;

        try newTypeNode.super.append(universal);
        try universal.sub.append(newTypeNode);

        try self.types.put(what, newTypeNode);

        return self.types.get(what) orelse unreachable;
    }

    pub fn draw(self: *Node, file: std.fs.File, allocator: Allocator, accumulatedName: std.ArrayList(u8)) !void {
        // getting following id

        const backlinkFollowingId = utils.getBacklinkFollowingId(self);

        const nodeHeader = try std.fmt.allocPrint(allocator, "subgraph cluster_{s}{} ", .{ accumulatedName.items, backlinkFollowingId });
        try file.writeAll(nodeHeader);
        try file.writeAll("{\n");
        try file.writeAll("style=\"rounded\"\n");

        // writing node label
        const nodeLabelName = try utils.fixName2(allocator, accumulatedName);
        const nodeLabel = try std.fmt.allocPrint(allocator, "label = \"{s}\";\n", .{nodeLabelName.items});
        // if (self.isGeneric) {
        //     const color = try std.fmt.allocPrint(allocator, "color = purple;\nstyle = filled;\n", .{});
        //     try file.writeAll(color);
        // }
        try file.writeAll(nodeLabel);

        // writing type nodes inside this node
        // for (self.types.items) |typeNode| {
        var it = self.types.valueIterator();
        while (it.next()) |typeNode| { // TODO: print not listed here nodes
            std.debug.print("COMPARING WITH {s}\n", .{typeNode.*.of});
            const typeNodeLabel = try utils.fixName(allocator, typeNode.*.of, false);

            const typeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, typeNode.*.of });
            var typeNodeStyle: []const u8 = "";
            switch (typeNode.*.kind) {
                .gin => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=yellow,style=filled", .{}),
                .gout => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=purple,style=filled", .{}),
                .open => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=sienna,style=filled", .{}),
                .close => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=sienna,style=filled", .{}),
                .syntetic => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=blue,style=filled", .{}),
                else => {},
            }

            const name = try std.fmt.allocPrint(allocator, "{s}{}[label=\"{s}\"{s}];\n", .{ typeNodeId, backlinkFollowingId, typeNodeLabel, typeNodeStyle });
            try file.writeAll(name);
        }

        // TODO: extract copypaste
        for (self.syntetics.items) |typeNode| {
            std.debug.print("DRAWING SYNTETIC {s} with {} following\n", .{ typeNode.*.of, typeNode.followings.items.len });

            const typeNodeLabel = try utils.fixName(allocator, typeNode.*.of, false);

            const tname = if (std.mem.eql(u8, typeNode.*.of, "?")) "syntetic" else typeNode.*.of;
            const typeNodeId = try std.fmt.allocPrint(allocator, "{s}{s}", .{ accumulatedName.items, tname });
            var typeNodeStyle: []const u8 = "";
            switch (typeNode.*.kind) {
                .gin => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=yellow,style=filled", .{}),
                .gout => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=purple,style=filled", .{}),
                .open => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=sienna,style=filled", .{}),
                .close => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=sienna,style=filled", .{}),
                .syntetic => typeNodeStyle = try std.fmt.allocPrint(allocator, ",color=blue,style=filled", .{}),
                else => {},
            }

            const name = try std.fmt.allocPrint(allocator, "{s}{}[label=\"{s}\"{s}];\n", .{ typeNodeId, backlinkFollowingId, typeNodeLabel, typeNodeStyle });
            try file.writeAll(name);
        }

        // writing function finished by this node
        for (self.endings.items) |decl| {
            std.debug.print("Found ending {s}\n", .{decl.name});
            const finished = try std.fmt.allocPrint(allocator, "{s}[color=darkgreen,style=filled,shape=signature];\n", .{decl.name});
            try file.writeAll(finished);
        }

        try file.writeAll("}\n");

        // for (self.types.items) |*typeNode| {
        it = self.types.valueIterator();
        while (it.next()) |typeNode| {
            std.debug.print("Continuing by {s}\n", .{typeNode.*.of});
            typeNode.*.preceding = self;
            try typeNode.*.draw(file, allocator, accumulatedName);
        }

        for (self.syntetics.items) |typeNode| {
            std.debug.print("Continuing by syntetic\n", .{});
            try typeNode.*.draw(file, allocator, accumulatedName);
        }
    }
};
