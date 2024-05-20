const std = @import("std");
const Allocator = std.mem.Allocator;

const queryParser = @import("../query_parser.zig");

const TypeC = queryParser.TypeC;
const TypeNode = @import("TypeNode.zig");
const Following = @import("following.zig").Following;

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

pub const Shard = struct {
    it: *TypeNode,
    reflection: *TypeNode,
};

pub const FollowingShard = struct {
    it: *Following,
    reflection: *Following,
};
