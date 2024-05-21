const std = @import("std");
const Allocator = std.mem.Allocator;

const queryParser = @import("../query_parser.zig");

const TypeC = queryParser.TypeC;
const TypeNode = @import("TypeNode.zig");
const Following = @import("following.zig").Following;
const Node = @import("Node.zig");

pub const Declaration = struct {
    name: []const u8,
    ty: *TypeC,
    id: usize = 0,

    pub fn init(allocator: Allocator, name: []const u8, ty: *TypeC) !*Declaration {
        const self = try allocator.create(Declaration);

        self.* = .{
            .name = name,
            .ty = ty,
        };

        return self;
    }
};

// TODO: now it only means function composition
pub const Expression = struct {
    inner: *Declaration,
    outer: *Declaration,

    pub fn format(
        this: Expression,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("({s}: {s}) ∘ ({s}: {s})", .{
            this.outer.name,
            this.outer.ty,
            this.inner.name,
            this.inner.ty,
        });
    }
};

fn Pair(comptime T: type) type {
    return struct {
        it: *T,
        reflection: *T,
    };
}

pub const Shard = Pair(TypeNode);

pub const FollowingShard = Pair(Following);

pub const Mirror = Pair(Node);
