const std = @import("std");
const Allocator = std.mem.Allocator;

const query = @import("../query.zig");
const TypeC = @import("../query.zig").TypeC;

pub const Declaration = struct {
    name: []const u8,
    ty: *query.TypeC,
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
