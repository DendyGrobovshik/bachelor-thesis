const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const RawDecl = @import("utils.zig").RawDecl;
const buildTree = @import("utils.zig").buildTree;

const utils = @import("../utils.zig");
const query0 = @import("../../query.zig");
const tree0 = @import("../tree.zig");
const Following = @import("../following.zig").Following;

test "label of following nodes are equal to string representation of types" {
    const types = [_][]const u8{
        "Array<U>",
        "Array<Array<U>>",
        "(Int -> String) -> Int -> String",
        "Int -> String -> Int -> String",
        "Array<String> -> Array<Int>",
        "Int -> Array<Int> -> Int",
        "Int -> (Int -> Array<U>) -> (Array<Vector<U>> -> String) -> String",
    };

    for (types) |tyStr| {
        const labelName = try getLabelName(tyStr);
        try std.testing.expectEqualStrings(tyStr, labelName);
    }
}

fn getLabelName(tyStr: []const u8) ![]const u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecl = RawDecl{ .ty = tyStr, .name = "foo" };
    const rawDecls = [_]RawDecl{rawDecl};

    var searchIndex = try buildTree(&rawDecls, allocator);

    const query = try tree0.parseQ(allocator, rawDecl.ty);
    const leaf = try searchIndex.sweetLeaf(query.ty, allocator);

    return utils.trimRightArrow(try (try leaf.getFollowing(null, Following.Kind.arrow, allocator)).to.labelName(allocator));
}
