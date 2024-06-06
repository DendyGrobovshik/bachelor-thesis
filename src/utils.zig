const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const main = @import("main.zig");
const queryParser = @import("query_parser.zig");
const TypeC = queryParser.TypeC;
const List = queryParser.List;


pub fn uncurry(typec: *TypeC, allocator: Allocator) TypeC {
    var current = typec;

    var inTypes = std.ArrayList(*TypeC).init(allocator);
    while (current.isFunction()) {
        try inTypes.append(current.ty.function.from);
        current = current.ty.function.to;
    }

    return List.init(allocator, inTypes);
}
