const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const utils = @import("utils.zig");
const engineUtils = @import("../utils.zig");
const buildTree = utils.buildTree;
const queryParser = @import("../../query_parser.zig");

const RawDecl = @import("utils.zig").RawDecl;

test "tree.extractAllDecls" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .name = "f1", .ty = "Array<T>" },
        RawDecl{ .name = "f2", .ty = "Array<Int, String>" },
        RawDecl{ .name = "f3", .ty = "Array<String -> Int>" },
        RawDecl{ .name = "f4", .ty = "Array<Optional<T>, (Int -> String), (Map<String, T>)>" },
        RawDecl{ .name = "f5", .ty = "Array<String -> (Xa -> Xb) -> Int>" },
        RawDecl{ .name = "f6", .ty = "Array<String, (Int, Bool)>" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const leaf = try searchIndex.sweetLeaf(query.ty, allocator);
        const printed = try engineUtils.typeToString(leaf, allocator, true);

        try std.testing.expectEqualStrings(rawDecl.ty, printed.str);
    }
}

// TODO: test for syntetic nodes correct name printing

// TODO: here can be fuzzing tests:
// - generate type
// - add type in tree
// - print type
// - compare it equal to reference
