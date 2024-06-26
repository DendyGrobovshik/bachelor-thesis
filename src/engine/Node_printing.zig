const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const EngineError = @import("error.zig").EngineError;

pub fn notEmptyTypeNodes(self: *Node, allocator: Allocator) Allocator.Error!std.ArrayList(*TypeNode) {
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

/// Collect path of types from ROOT to current Node as string.
// Append index of Following for which the transition was made
pub fn stringPath(current: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    if (current.by == &constants.PREROOT) {
        return "";
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{
        try current.by.stringPath(allocator),
        try byFollowingIndex(current, allocator),
    });
}

/// Return string representation of index of following by which
/// the transition from previous TypeNode to current Node was made.
fn byFollowingIndex(self: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    var result: usize = 0;

    for (self.by.followings.items, 0..) |following, i| {
        if (following.to == self) {
            result = i;
        }
    }

    return try std.fmt.allocPrint(allocator, "{}", .{result});
}

pub fn labelName(self: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    if (self.by == &constants.PREROOT) {
        return "";
    }

    const byFollowing = utils.followingTo(self);
    const arrow = byFollowing.arrow();
    return self.by.partName(arrow, allocator);
}

// TODO: doublecheck!!!
pub fn isEmpty(self: *Node) bool {
    return self.endings.items.len == 0 and
        self.named.count() == 0 and
        (self.universal.followings.items.len == 0 and
        self.universal.childs.count() == 0 and
        self.opening.followings.items.len == 0 and
        self.opening.childs.count() == 0 and
        self.closing.followings.items.len == 0 and
        self.closing.childs.count() == 0);
}

pub fn draw(self: *Node, file: std.fs.File, allocator: Allocator) EngineError!void {
    if (self.isEmpty()) {
        return;
    }

    const typeNodes = try self.notEmptyTypeNodes(allocator);

    try file.writeAll(try std.fmt.allocPrint(allocator, "subgraph \"cluster_{s}\"", .{try self.stringPath(allocator)}));
    try file.writeAll("{\n");
    try file.writeAll("style=\"rounded\"\n");
    var label = try self.labelName(allocator);
    if (label.len == 0) {
        label = "ROOT";
    }
    try file.writeAll(try std.fmt.allocPrint(allocator, "label=\"{s}\";\n", .{
        try utils.fixLabel(utils.trimRightArrow(label), allocator),
    }));

    for (self.endings.items) |decl| {
        // NOTE: keep in mind 'decl' prefix
        try file.writeAll(try std.fmt.allocPrint(allocator, "\"decl{s}\"[label=\"{s}\",color=darkgreen,style=filled,shape=signature];\n", .{
            decl.name,
            decl.name,
        }));
    }

    for (typeNodes.items) |typeNode| {
        try typeNode.draw(file, allocator);
    }

    try file.writeAll("}\n");

    for (typeNodes.items) |typeNode| {
        try typeNode.drawConnections(file, allocator);
    }
}

pub fn getTypeInAngles(node: *Node, allocator: Allocator) Allocator.Error![]const u8 {
    // it collect type until matching opening node
    // simple idea: suffix = prefixsuffix - prefix
    const presuf = try node.labelName(allocator);
    const open = utils.getOpenParenthesis(node.by);
    const pre = try open.followings.getLast().to.labelName(allocator); //TODO: check if it's always one outcoming from open parenthesis

    return utils.trimRightArrow(utils.onlySuffix(pre, presuf));
}
