const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const main = @import("main.zig");
const query = @import("query.zig");
const TypeC = query.TypeC;
const List = query.List;

pub fn randomName(allocator: Allocator) anyerror![]const u8 {
    var name = std.ArrayList(u8).init(allocator);

    for (0..main.rnd.random().intRangeLessThan(u3, 1, 5)) |_| {
        try name.append(main.rnd.random().intRangeLessThan(u8, 65, 90));
    }

    return name.items;
}

pub fn uncurry(typec: *TypeC, allocator: Allocator) TypeC {
    var current = typec;

    var inTypes = std.ArrayList(*TypeC).init(allocator);
    while (current.isFunction()) {
        try inTypes.append(current.ty.function.from);
        current = current.ty.function.to;
    }

    return List.init(allocator, inTypes);
}
