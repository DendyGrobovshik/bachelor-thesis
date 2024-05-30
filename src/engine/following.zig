const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const EngineError = @import("error.zig").EngineError;
const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");

pub const Following = struct {
    pub const Kind = enum {
        arrow, // simple function arrow
        generic, // between generic and nominative
        fake, // between brace TypeNode
        comma, // was originally comma
    };

    to: *Node, // to what node
    backlink: ?*TypeNode, // same as de Bruijn index (helps to disinguish generics)
    kind: Kind = Kind.arrow,

    pub fn init(allocator: Allocator, of: *TypeNode, backlink: ?*TypeNode, kind: Kind) Allocator.Error!*Following {
        const to = try Node.init(allocator, of);
        const self = try allocator.create(Following);

        self.* = .{
            .to = to,
            .backlink = backlink,
            .kind = kind,
        };

        return self;
    }

    pub fn color(self: *Following) []const u8 {
        return switch (self.kind) {
            .arrow => "black",
            .fake => "grey",
            .generic => "cyan",
            .comma => "blue",
        };
    }

    pub fn arrow(self: *Following) []const u8 {
        return switch (self.kind) {
            .arrow => " -> ",
            .fake => "",
            .generic => " -> ",
            .comma => ", ",
        };
    }

    pub fn isGnominative(self: *Following) bool {
        return switch (self.kind) {
            .generic => true,
            else => false,
        };
    }

    pub fn eq(self: *Following, other: *Following) bool {
        return self.kind == other.kind; // TODO: and backlink are equal
    }
};
