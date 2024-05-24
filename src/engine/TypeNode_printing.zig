const TypeNode = @import("TypeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");
const utils = @import("utils.zig");

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

pub fn fullPathName(self: *TypeNode, allocator: Allocator) Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(main.gallocator, "{s}{s}", .{
        try self.of.fullPathName(allocator),
        try self.name(allocator),
    });
}

pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator) anyerror!void {
    try file.writeAll(try std.fmt.allocPrint(allocator, "{s}[label=\"{s}\",color={s},style=filled];\n", .{
        try self.fullPathName(allocator),
        try utils.fixLabel(try self.labelName(allocator), allocator),
        self.color(),
    }));
}

pub fn drawConnections(self: *TypeNode, file: std.fs.File, allocator: Allocator) !void {
    var it = self.childs.keyIterator();
    while (it.next()) |child| {
        if (child.*.notEmpty()) {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[color=red,style=filled];\n", .{
                try self.fullPathName(allocator),
                try child.*.fullPathName(allocator),
            }));
        }
    }

    for (self.followings.items) |following| {
        if (!following.to.isEmpty()) {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[lhead=cluster_{s},color=\"{s}\",style=filled];\n", .{
                try self.fullPathName(allocator),
                try following.to.universal.fullPathName(allocator),
                try following.to.fullPathName(allocator),
                following.color(),
            }));

            try following.to.draw(file, allocator);
        }
    }
}

pub fn synteticName(self: *TypeNode, isLabel: bool, allocator: Allocator) Allocator.Error![]const u8 {
    var result = std.ArrayList(u8).init(allocator);

    var it = self.parents.keyIterator();
    while (it.next()) |parent| {
        if (isLabel) {
            if (parent.*.of != self.of) {
                const res = try parent.*.partName(" -> ", allocator);
                try result.appendSlice(res[0 .. res.len - 4]); // TODO: fix or remove arrow
            } else {
                try result.appendSlice(try parent.*.labelName(allocator));
            }
            try result.appendSlice(" & ");
        } else {
            try result.appendSlice(try parent.*.of.fullPathName(allocator));
            try result.appendSlice("and");
        }
    }

    if (self.parents.count() > 0) {
        return result.items[0 .. result.items.len - 3];
    }

    return result.items; // TODO: check allocator releasing
}

pub fn partName(self: *TypeNode, arrow: []const u8, allocator: Allocator) ![]const u8 {
    if (self.isClosing()) { // current is closing
        const prevTypeNode = self.of.by;
        if (prevTypeNode.isGnominative()) { // and previous is gnominative
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
