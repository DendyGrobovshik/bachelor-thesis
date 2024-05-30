const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const buildTree = utils.buildTree;
const queryParser = @import("../../query_parser.zig");

const RawDecl = @import("utils.zig").RawDecl;
const Variance = @import("../variance.zig").Variance;

test "function output variance in covariant" {
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
        const ty = try queryParser.parseQuery(allocator, "Int -> Int");

        const decls = try searchIndex.findDeclarationsWithVariants(ty.ty, Variance.covariant);

        try std.testing.expectEqual(2, decls.count());

        try std.testing.expect(utils.inDecls("exact", decls));
        try std.testing.expect(utils.inDecls("yes", decls));
    }

    {
        const ty = try queryParser.parseQuery(allocator, "Int -> Bool");
        const decls = try searchIndex.findDeclarations(ty.ty);

        try std.testing.expectEqual(1, decls.count());

        try std.testing.expect(utils.inDecls("no", decls));
    }
}

test "function input is contravariant" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int -> Int", .name = "yes" },
        RawDecl{ .ty = "Int -> IntEven", .name = "yes2" },
        RawDecl{ .ty = "Int -> Bool", .name = "no" },
        RawDecl{ .ty = "IntEven -> Int", .name = "exact" }, // no due to function is contravariant
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    {
        const ty = try queryParser.parseQuery(allocator, "IntEven -> Int");

        const decls = try searchIndex.findDeclarationsWithVariants(ty.ty, Variance.covariant);

        try std.testing.expectEqual(3, decls.count());

        try std.testing.expect(utils.inDecls("exact", decls));
        try std.testing.expect(utils.inDecls("yes", decls));
        try std.testing.expect(utils.inDecls("yes2", decls));
    }

    {
        const ty = try queryParser.parseQuery(allocator, "Int -> Bool");
        const decls = try searchIndex.findDeclarations(ty.ty);

        try std.testing.expectEqual(1, decls.count());

        try std.testing.expect(utils.inDecls("no", decls));
    }
}

test "function input variance applies for all types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "IntEven, IntEven -> Int", .name = "exact" },
        RawDecl{ .ty = "Int, IntEven -> Int", .name = "yes" },
        RawDecl{ .ty = "IntEven, Int -> Int", .name = "yes2" },
        RawDecl{ .ty = "Int, Int -> Int", .name = "yes3" },
        RawDecl{ .ty = "Int, Int -> IntEven", .name = "yes4" },
        RawDecl{ .ty = "Int, Bool -> IntEven", .name = "no" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    {
        const ty = try queryParser.parseQuery(allocator, "IntEven, IntEven -> Int");

        const decls = try searchIndex.findDeclarationsWithVariants(ty.ty, Variance.covariant);

        try std.testing.expectEqual(5, decls.count());

        try std.testing.expect(utils.inDecls("exact", decls));
        try std.testing.expect(utils.inDecls("yes", decls));
        try std.testing.expect(utils.inDecls("yes2", decls));
        try std.testing.expect(utils.inDecls("yes3", decls));
        try std.testing.expect(utils.inDecls("yes4", decls));
    }
}

test "generics invariant by default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Array<Int> -> Array<Int>", .name = "f1" },
        RawDecl{ .ty = "Array<IntEven> -> Array<IntEven>", .name = "f2" },
        RawDecl{ .ty = "Array<Int> -> Array<IntEven>", .name = "f3" },
        RawDecl{ .ty = "Array<IntEven> -> Array<Int>", .name = "f4" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(1, decls.count());
        var it = decls.keyIterator();
        try std.testing.expectEqualStrings(rawDecl.name, it.next().?.*.name);
    }
}

test "lists are covariant by default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "(Int, Int)", .name = "exact" },
        RawDecl{ .ty = "(Int, IntEven)", .name = "yes1" },
        RawDecl{ .ty = "(IntEven, Int)", .name = "yes2" },
        RawDecl{ .ty = "(IntEven, IntEven)", .name = "yes3" },
        RawDecl{ .ty = "(Int, Any)", .name = "no1" },
        RawDecl{ .ty = "(Ant, IntEven)", .name = "no2" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    {
        const ty = try queryParser.parseQuery(allocator, "(Int, Int)");

        const decls = try searchIndex.findDeclarationsWithVariants(ty.ty, Variance.covariant);

        try std.testing.expectEqual(4, decls.count());

        try std.testing.expect(utils.inDecls("exact", decls));
        try std.testing.expect(utils.inDecls("yes1", decls));
        try std.testing.expect(utils.inDecls("yes2", decls));
        try std.testing.expect(utils.inDecls("yes3", decls));
    }
}
