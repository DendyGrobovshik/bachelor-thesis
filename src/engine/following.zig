const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const EngineError = @import("error.zig").EngineError;
const Node = @import("node.zig").Node;
const TypeNode = @import("typeNode.zig").TypeNode;

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

    pub fn init(allocator: Allocator, of: *TypeNode, backlink: ?*TypeNode) EngineError!*Following {
        const to = try Node.init(allocator, of);
        const self = try allocator.create(Following);

        self.* = .{
            .to = to,
            .backlink = backlink,
            .kind = Kind.arrow,
        };

        return self;
    }

    pub fn color(self: *Following) []const u8 {
        return switch (self.kind) {
            .arrow => "black",
            .fake => "grey",
            .generic => "green",
            .comma => "yellow",
        };
    }
};
