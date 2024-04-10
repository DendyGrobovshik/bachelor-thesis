const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const SegmentedList = @import("std").SegmentedList;

const TypeNode = @import("typeNode.zig").TypeNode;
const Declaration = @import("tree.zig").Declaration;
const SEGMENTED_LIST_SIZE = @import("../constants.zig").SEGMENTED_LIST_SIZE;

pub const Node = struct {
    layer: u32,

    types: std.ArrayList(TypeNode),
    endings: std.ArrayList(Declaration),

    name: []const u8,

    pub fn init(allocator: Allocator, name: []const u8, layer: u32) !Node {
        var types = std.ArrayList(TypeNode).init(allocator);
        const universal = TypeNode.init(allocator, "T");
        try types.append(universal); // universal type

        std.debug.print("Node inited {}\n", .{types.items.len});

        const endings = std.ArrayList(Declaration).init(allocator);

        return .{
            .layer = layer,
            .types = types,
            .endings = endings,
            .name = name,
        };
    }

    // TODO: check if not in
    pub fn insertTypeNode(self: *Node, typeNode_: TypeNode) !void {
        // TODO:
        // - use outer solver
        // - replcaing ArrayList of types with Map can enhance inserting performace
        // hwo to fast insert according to constraints?

        try self.types.append(typeNode_);
        // var typeNode = &self.types.items[self.types.items.len - 1];
        var typeNode: *TypeNode = undefined;
        for (self.types.items) |*typeNode__| {
            if (std.mem.eql(u8, typeNode__.name, typeNode_.name)) {
                typeNode = typeNode__;
            }
        }

        for (self.types.items) |*otherTypeNode_| {
            var otherTypeNode = otherTypeNode_;

            if (typeNode.isSubstitutable(otherTypeNode.*)) {
                std.debug.print("SUBSTABLE {s} < {s}\n", .{ self.name, typeNode_.name });
                try typeNode.super.append(otherTypeNode);
                try otherTypeNode.sub.append(typeNode);
            }
            if (otherTypeNode.isSubstitutable(typeNode.*)) {
                std.debug.print("SUBSTABLE {s} < {s}\n", .{ typeNode_.name, self.name });
                try typeNode.sub.append(otherTypeNode);
                try otherTypeNode.super.append(typeNode);
            }
        }
    }

    // using result of this functions and knowing variance
    // can solve substition problem
    pub fn getTypeNode(self: *Node, name: []const u8) ?*TypeNode {
        for (self.types.items) |*typeNode| {
            if (std.mem.eql(u8, typeNode.*.name, name)) {
                return typeNode;
            }
        }

        return null;
    }

    pub fn draw(self: *const Node, file: std.fs.File, allocator: Allocator, prevNodeName: []const u8) !void {
        const nodeHeader = try std.fmt.allocPrint(allocator, "subgraph cluster_{s}{}{s} ", .{ self.name, self.layer, prevNodeName });
        try file.writeAll(nodeHeader);
        try file.writeAll("{\n");
        try file.writeAll("style=\"rounded\"\n");

        var label: []u8 = undefined;
        if (std.mem.eql(u8, self.name, "root")) {
            label = try std.fmt.allocPrint(allocator, "", .{});
        } else if (std.mem.eql(u8, self.name, "functionopening322")) {
            label = try std.fmt.allocPrint(allocator, "label = \"(\";\n", .{});
        } else if (std.mem.eql(u8, self.name, "functionclosing322")) {
            label = try std.fmt.allocPrint(allocator, "label = \")\";\n", .{});
        } else {
            label = try std.fmt.allocPrint(allocator, "label = \"by {s}\";\n", .{self.name});
        }
        try file.writeAll(label);

        for (self.types.items) |typeNode| {
            std.debug.print("COMPARING WITH {s}\n", .{typeNode.name});
            var typeNodeLabel: []const u8 = undefined;
            if (std.mem.eql(u8, typeNode.name, "functionclosing322")) {
                typeNodeLabel = try std.fmt.allocPrint(allocator, ")", .{});
            } else if (std.mem.eql(u8, typeNode.name, "functionopening322")) {
                typeNodeLabel = try std.fmt.allocPrint(allocator, "(", .{});
            } else {
                typeNodeLabel = typeNode.name;
            }

            const nodeArgs = .{ typeNode.name, self.name, self.layer, prevNodeName, typeNodeLabel };
            const name = try std.fmt.allocPrint(allocator, "{s}{s}{}{s}[label=\"{s}\"]", nodeArgs);
            try file.writeAll(name);
            try file.writeAll(";\n");
        }

        for (self.endings.items) |decl| {
            const finished = try std.fmt.allocPrint(allocator, "{s} [color=darkgreen,style=filled];\n", .{decl.name});
            try file.writeAll(finished);
        }

        try file.writeAll("}\n");

        for (self.types.items) |*typeNode| {
            typeNode.of = self;
            try typeNode.draw(file, allocator, self.name, prevNodeName);
        }
    }
};
