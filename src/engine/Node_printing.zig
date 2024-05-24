const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const constants = @import("constants.zig");
const utils = @import("utils.zig");

pub fn byId(self: *Node) Allocator.Error![]const u8 {
    var result: usize = 0;

    for (self.by.followings.items, 0..) |following, i| {
        if (following.to == self) {
            result = i;
        }
    }

    return try std.fmt.allocPrint(main.gallocator, "{}", .{result});
}

pub fn notEmptyTypeNodes(self: *Node, allocator: Allocator) anyerror!std.ArrayList(*TypeNode) {
    var result = std.ArrayList(*TypeNode).init(allocator);

    var it = self.named.valueIterator();
    while (it.next()) |typeNode| {
        try result.append(typeNode.*);
    }

    for (self.syntetics.items) |typeNode| {
        try result.append(typeNode);
    }

    if (self.universal.notEmpty()) {
        try result.append(self.universal);
    }

    if (self.opening.notEmpty()) {
        try result.append(self.opening);
    }

    if (self.closing.notEmpty()) {
        try result.append(self.closing);
    }

    return result;
}

pub fn fullPathName(self: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    if (self.by == &constants.PREROOT) {
        return "";
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{
        try self.by.fullPathName(allocator),
        try self.byId(),
    });
}

pub fn labelName(self: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    if (self.by == &constants.PREROOT) {
        return "";
    }

    const following = utils.followingTo(self);
    const arrow = following.arrow();
    return self.by.partName(arrow, allocator);
}

// TODO: doublecheck!!!
pub fn isEmpty(self: *Node) bool {
    return self.endings.items.len == 0 and
        self.named.count() == 0 and
        (self.universal.followings.items.len == 0 and
        self.universal.childs.count() == 2 and // open and closing
        self.opening.followings.items.len == 0 and
        self.opening.childs.count() == 0 and
        self.closing.followings.items.len == 0 and
        self.closing.childs.count() == 0);
}

pub fn draw(self: *Node, file: std.fs.File, allocator: Allocator) anyerror!void {
    if (self.isEmpty()) {
        // return;
    }

    const typeNodes = try self.notEmptyTypeNodes(allocator);

    try file.writeAll(try std.fmt.allocPrint(allocator, "subgraph cluster_{s}", .{try self.fullPathName(allocator)}));
    try file.writeAll("{\n");
    try file.writeAll("style=\"rounded\"\n");
    var label = try self.labelName(allocator);
    if (label.len == 0) {
        label = "ROOT";
    }
    try file.writeAll(try std.fmt.allocPrint(allocator, "label = \"{s}\";\n", .{
        try utils.fixLabel(utils.trimRightArrow(label), allocator),
    }));

    for (self.endings.items) |decl| {
        try file.writeAll(try std.fmt.allocPrint(allocator, "{s}[color=darkgreen,style=filled,shape=signature];\n", .{decl.name}));
    }

    for (typeNodes.items) |typeNode| {
        try typeNode.draw(file, allocator);
    }

    try file.writeAll("}\n");

    for (typeNodes.items) |typeNode| {
        try typeNode.drawConnections(file, allocator);
    }
}

pub fn getTypeInAngles(node: *Node, allocator: Allocator) ![]const u8 {
    // it collect type until matching opening node
    // TODO: here is cringe idea: suffix = prefixsuffix - prefix
    const presuf = try node.labelName(allocator);
    const open = utils.getOpenParenthesis(node.by);
    const pre = try open.followings.getLast().to.labelName(allocator); //TODO: check if it's always one outcoming from open parenthesis
    var suf: []const u8 = "";
    // handling pre="(("" and presuf"(Array<U> ->"
    for (0..pre.len) |start| {
        const suffixOfPrefix = pre[0..(pre.len - start)];
        const match = std.mem.eql(u8, suffixOfPrefix, presuf[0..(pre.len - start)]);

        if (match) {
            suf = presuf[(pre.len - start)..];
            break;
        }
    }

    if (suf.len == 0) {
        std.debug.print("Error: prefix='{s}', full='{s}', suffix='{s}'. Suffix shouldn't be empty.\n", .{ pre, presuf, suf });
        unreachable;
    }

    return utils.trimRightArrow(suf);
}
