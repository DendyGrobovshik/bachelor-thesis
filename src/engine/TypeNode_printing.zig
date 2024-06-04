const TypeNode = @import("TypeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");
const utils = @import("utils.zig");
const tree = @import("tree.zig");
const subtyping = @import("subtyping.zig");

const AutoHashSet = utils.AutoHashSet;
const Following = @import("following.zig").Following;
const EngineError = @import("error.zig").EngineError;

pub fn name(self: *TypeNode, allocator: Allocator) Allocator.Error![]const u8 {
    return switch (self.kind) {
        .universal => "U",
        .syntetic => try self.synteticName(false, allocator),
        .nominative => self.kind.nominative,
        .gnominative => self.kind.gnominative,
        .opening => "opening322",
        .closing => "closing322",
    };
}

pub fn labelName(self: *TypeNode, allocator: Allocator) ![]const u8 {
    return switch (self.kind) {
        .universal => "U",
        .syntetic => try self.synteticName(true, allocator),
        .nominative => self.kind.nominative,
        .gnominative => self.kind.gnominative,
        .opening => "(",
        .closing => ")",
    };
}

pub fn color(self: *TypeNode) []const u8 {
    return switch (self.kind) {
        .universal => "yellow",
        .syntetic => "blue",
        .nominative => "lightgrey",
        .gnominative => "purple",
        .opening => "sienna",
        .closing => "sienna",
    };
}

/// string path to Node of current TypeNode + name of current TypeNode
pub fn stringPath(self: *TypeNode, allocator: Allocator) Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{
        try self.of.stringPath(allocator),
        try self.name(allocator),
    });
}

pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator) EngineError!void {
    try file.writeAll(try std.fmt.allocPrint(allocator, "{s}[label=\"{s}\",color={s},style=filled];\n", .{
        try self.stringPath(allocator),
        try utils.fixLabel(try self.labelName(allocator), allocator),
        self.color(),
    }));
}

pub fn drawConnections(self: *TypeNode, file: std.fs.File, allocator: Allocator) !void {
    var it = self.childs.keyIterator();
    while (it.next()) |child| {
        if (child.*.notEmpty()) {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[color=red,style=filled];\n", .{
                try self.stringPath(allocator),
                try child.*.stringPath(allocator),
            }));
        }
    }

    for (self.followings.items) |following| {
        if (!following.to.isEmpty()) {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[lhead=cluster_{s},color=\"{s}\",style=filled];\n", .{
                try self.stringPath(allocator),
                try following.to.universal.stringPath(allocator),
                try following.to.stringPath(allocator),
                following.color(),
            }));

            try following.to.draw(file, allocator);
        }
    }
}

pub fn synteticName(self: *TypeNode, isLabel: bool, allocator: Allocator) Allocator.Error![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    const delimiter = if (isLabel) " & " else "and";

    const minorants = try subtyping.getMinorantOfNominativeUpperBounds(self, allocator);

    var it = minorants.keyIterator();
    while (it.next()) |minorant| {
        if (isLabel) {
            if (minorant.*.of != self.of) {
                const res = try minorant.*.partName(" -> ", allocator);
                try result.appendSlice(res[0 .. res.len - 4]); // TODO: fix or remove arrow
            } else {
                try result.appendSlice(try minorant.*.labelName(allocator));
            }
            try result.appendSlice(delimiter);
        } else {
            try result.appendSlice(try minorant.*.name(allocator));
            try result.appendSlice(delimiter);
        }
    } else {
        return result.items[0 .. result.items.len - delimiter.len];
    }

    return result.items;
}

pub fn partName(self: *TypeNode, arrow: []const u8, allocator: Allocator) ![]const u8 {
    if (self.kind == TypeNode.Kind.closing) {
        const prevTypeNode = self.of.by;
        if (prevTypeNode.kind == TypeNode.Kind.gnominative) {
            return try std.fmt.allocPrint(allocator, "{s}{s}<{s}>{s}", .{
                try utils.getOpenParenthesis(self).of.labelName(allocator), // type before this nominive with generic
                try prevTypeNode.labelName(allocator), // gnominative
                try prevTypeNode.of.getTypeInAngles(allocator), // type paremeter
                arrow,
            });
        }
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        try self.of.labelName(allocator),
        try self.labelName(allocator),
        arrow,
    });
}

pub fn originalTypeName(of: *TypeNode, allocator: Allocator) Allocator.Error![]const u8 {
    switch (of.kind) {
        // .nominative =>
        .gnominative => {
            const withGeneric = try std.fmt.allocPrint(allocator, "{s}<Any>", .{
                try of.name(allocator),
            });

            // std.debug.print("result: '{s}'\n", .{withGeneric});
            return withGeneric;
        },
        else => return try of.name(allocator),
    }
}
