const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const Declaration = @import("tree.zig").Declaration;
const Node = @import("node.zig").Node;
const SEGMENTED_LIST_SIZE = @import("../constants.zig").SEGMENTED_LIST_SIZE;

pub const TypeNode = struct {
    name: []const u8,
    super: std.ArrayList(*TypeNode),
    sub: std.ArrayList(*TypeNode),

    following: ?Node, // TODO: why it's not ptr?
    of: ?*const Node,

    pub fn init(allocator: Allocator, name: []const u8) TypeNode {
        const super = std.ArrayList(*TypeNode).init(allocator);
        const sub = std.ArrayList(*TypeNode).init(allocator);

        return .{
            .name = name,
            .super = super,
            .sub = sub,
            .following = null,
            .of = null,
        };
    }

    // TODO:
    pub fn isSubstitutable(self: TypeNode, where: TypeNode) bool {
        if (std.mem.eql(u8, self.name, "functionopening322") or std.mem.eql(u8, self.name, "functionclosing322")) {
            return false;
        }

        if (std.mem.eql(u8, where.name, "T")) {
            return true;
        }

        const Pair = struct { []const u8, []const u8 };

        const pairs = [_]Pair{
            .{ "String", "Collection" },
        };

        for (pairs) |pair| {
            if (std.mem.eql(u8, self.name, pair[0]) and std.mem.eql(u8, where.name, pair[1])) {
                return true;
            }
        }

        return false;
    }

    pub fn draw(self: *const TypeNode, file: std.fs.File, allocator: Allocator, of: []const u8, prevNodeName: []const u8) anyerror!void {
        if (self.following) |following| {
            const crazyArgs = .{ self.name, of, following.layer - 1, prevNodeName, following.name, following.layer, of, following.name, following.layer, of };
            const toNextNode = try std.fmt.allocPrint(allocator, "{s}{s}{}{s} -> T{s}{}{s}[lhead = cluster_{s}{}{s}];\n", crazyArgs);
            try file.writeAll(toNextNode);

            try following.draw(file, allocator, of);
        }

        std.debug.print("Super nodes {}\n", .{self.super.items.len});
        for (self.super.items) |super| {
            std.debug.print("drawing super of {s} < {s}\n", .{ self.name, super.name });
            const fromArgs = .{ super.name, super.of.?.name, super.of.?.layer, prevNodeName, self.name, self.of.?.name, self.of.?.layer, prevNodeName };
            const fromSuper = try std.fmt.allocPrint(allocator, "{s}{s}{}{s} -> {s}{s}{}{s};\n", fromArgs);
            try file.writeAll(fromSuper);
        }
    }
};
