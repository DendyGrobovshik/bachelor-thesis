const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const RawDecl = @import("utils.zig").RawDecl;
const buildTree = @import("utils.zig").buildTree;
const utils = @import("utils.zig");

const query0 = @import("../../query.zig");
const tree0 = @import("../tree.zig");
const Variance = @import("../tree.zig").Variance;

test "simple search with variance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int -> Int", .name = "exact" },
        RawDecl{ .ty = "Int -> IntEven", .name = "yes" },
        RawDecl{ .ty = "Int -> Bool", .name = "no" },
        RawDecl{ .ty = "IntEven -> Int", .name = "no2" }, // no due to function is contravariant
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    {
        const ty = try tree0.parseQ(allocator, "Int -> Int");

        const decls = try searchIndex.findDeclarationsWithVariants(ty.ty, Variance.covariant);

        try std.testing.expectEqual(2, decls.items.len);

        try std.testing.expect(utils.inArrayOfDecls("exact", decls));
        try std.testing.expect(utils.inArrayOfDecls("yes", decls));
    }

    {
        const ty = try tree0.parseQ(allocator, "Int -> Bool");
        const decls = try searchIndex.findDeclarations(ty.ty);

        try std.testing.expectEqual(1, decls.items.len);

        try std.testing.expectEqualStrings("no", decls.items[0].name);
    }
}
