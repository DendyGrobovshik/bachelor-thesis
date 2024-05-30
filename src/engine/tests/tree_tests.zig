const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const buildTree = utils.buildTree;

const RawDecl = @import("utils.zig").RawDecl;
const Variance = @import("../variance.zig").Variance;

// TODO: add more tests

test "tree.extractAllDecls" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .name = "f1", .ty = "String -> Int" },
        RawDecl{ .name = "f2", .ty = "Int -> Bool" },
        RawDecl{ .name = "f3", .ty = "String -> IntEven" },
        RawDecl{ .name = "f4", .ty = "Array<T> -> Collection<Int>" },
        RawDecl{ .name = "f5", .ty = "Collection<Int> -> Bool" },
        RawDecl{ .name = "f6", .ty = "Abc -> T where T < ToString & Printable" },
        RawDecl{ .name = "f7", .ty = "T -> Xyz where T < ToString " },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    const decls = try searchIndex.extractAllDecls(allocator);

    try std.testing.expectEqual(7, decls.count());

    for (rawDecls) |rawDecl| {
        try std.testing.expect(utils.inDecls(rawDecl.name, decls));
    }
}
