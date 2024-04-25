const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const main = @import("main.zig");
const query = @import("query.zig");

pub fn randomName(allocator: Allocator) anyerror![]const u8 {
    var name = std.ArrayList(u8).init(allocator);

    for (0..main.rnd.random().intRangeLessThan(u3, 1, 5)) |_| {
        try name.append(main.rnd.random().intRangeLessThan(u8, 65, 90));
    }

    return name.items;
}
