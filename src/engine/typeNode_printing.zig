const TypeNode = @import("typeNode.zig");

const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const main = @import("../main.zig");
const utils = @import("utils.zig");

pub fn name(self: *TypeNode) ![]const u8 {
    return switch (self.kind) {
        .universal => "U",
        .syntetic => try self.synteticName(false),
        .nominative => self.kind.nominative,
        .gnominative => self.kind.gnominative,
        .opening => "opening322",
        .closing => "closing322",
    };
}

pub fn labelName(self: *TypeNode) ![]const u8 {
    return switch (self.kind) {
        .universal => "U",
        .syntetic => try self.synteticName(true),
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

pub fn fullPathName(self: *TypeNode) Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(main.gallocator, "{s}{s}", .{ try self.of.fullPathName(), try self.name() });
}

pub fn draw(self: *TypeNode, file: std.fs.File, allocator: Allocator) anyerror!void {
    try file.writeAll(try std.fmt.allocPrint(allocator, "{s}[label=\"{s}\",color={s},style=filled];\n", .{
        try self.fullPathName(),
        try self.labelName(),
        self.color(),
    }));
}

pub fn drawConnections(self: *TypeNode, file: std.fs.File, allocator: Allocator) !void {
    for (self.childs.items) |child| {
        if (child.notEmpty()) {
            try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[color=red,style=filled];\n", .{
                try self.fullPathName(),
                try child.fullPathName(),
            }));
        }
    }

    for (self.followings.items) |following| {
        try file.writeAll(try std.fmt.allocPrint(allocator, "{s} -> {s}[lhead=cluster_{s},color=\"{s}\",style=filled];\n", .{
            try self.fullPathName(),
            try following.to.universal.fullPathName(),
            try following.to.fullPathName(),
            following.color(),
        }));

        try following.to.draw(file, allocator);
    }
}

pub fn synteticName(self: *TypeNode, isLabel: bool) Allocator.Error![]const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator); // TODO:

    for (self.parents.items[0 .. self.parents.items.len - 1]) |parent| {
        if (isLabel) {
            if (parent.of != self.of) {
                const res = try parent.partName(" -> ", main.gallocator);
                try result.appendSlice(res[0 .. res.len - 4]); // TODO: fix or remove arrow
            } else {
                try result.appendSlice(try parent.labelName());
            }
            try result.appendSlice(" & ");
        } else {
            try result.appendSlice(try parent.of.fullPathName());
            try result.appendSlice("and");
        }
    }

    // TODO: collapse with previous
    const parent = self.parents.getLast();
    if (isLabel) {
        if (parent.of != self.of) {
            const res = try parent.partName(" -> ", main.gallocator);
            try result.appendSlice(res[0 .. res.len - 4]); // TODO: fix or remove arrow
        } else {
            try result.appendSlice(try parent.labelName());
        }
    } else {
        try result.appendSlice(try parent.of.fullPathName());
    }

    return result.items; // TODO: check allocator releasing
}

pub fn partName(self: *TypeNode, arrow: []const u8, allocator: Allocator) ![]const u8 {
    if (self.isClosing()) { // current is closing
        const prevTypeNode = self.of.by;
        if (prevTypeNode.isGnominative()) { // and previous is gnominative
            return try std.fmt.allocPrint(allocator, "{s}{s}<{s}>{s}", .{
                try utils.getOpenParenthesis(self).of.labelName(allocator), // type before this nominive with generic
                try prevTypeNode.labelName(), // gnominative
                try prevTypeNode.of.getTypeInAngles(allocator), // type paremeter
                arrow,
            });
        }
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        try self.of.labelName(allocator),
        try self.labelName(),
        arrow,
    });
}
