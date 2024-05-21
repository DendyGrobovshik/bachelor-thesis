const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const queryParser = @import("../../query_parser.zig");
const buildTree = @import("utils.zig").buildTree;

const RawDecl = @import("utils.zig").RawDecl;
const Tree = @import("../tree.zig").Tree;

test "higher order functions are not mixed with common" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "String -> Int", .name = "f" },
        RawDecl{ .ty = "Int -> Bool", .name = "g" },
        RawDecl{ .ty = "String -> IntEven", .name = "f2" },
    };
    var tree = try buildTree(&rawDecls, allocator);

    const in = try queryParser.parseQuery(allocator, "String");
    const out = try queryParser.parseQuery(allocator, "Bool");
    const expressions = try tree.composeExpression(in.ty, out.ty);

    try std.testing.expectEqual(2, expressions.items.len);

    const firstExpr = try std.fmt.allocPrint(allocator, "{s}", .{expressions.items[0]});
    try std.testing.expectEqualStrings("(g: Int -> Bool) ∘ (f: String -> Int)", firstExpr);
    const secondExpr = try std.fmt.allocPrint(allocator, "{s}", .{expressions.items[1]});
    try std.testing.expectEqualStrings("(g: Int -> Bool) ∘ (f2: String -> IntEven)", secondExpr);
}
