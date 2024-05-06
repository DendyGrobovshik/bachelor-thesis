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

        "String -> Int",
        "Array<Int> -> Int",
        "(Int -> String) -> Int -> String",
        "Int -> String -> Int -> String",
        "U -> U",
        "Array<String> -> Array<Int>",
        "Array<Array<U>>",
        "Int -> Array<Array<U>>",
        "HashMap<Int, String> -> Int",
        "Array<Int>",
        "Array<Int>",
        // "(String, Int)", TODO: fix parenthesis printing
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

    const following = try leaf.getFollowing(null, Following.Kind.arrow, allocator);
    const label = try following.to.labelName(allocator);

    return utils.trimRightArrow(label);
}

test "label of following nodes with constraints are equal to constraints" {
    const Pair = struct {
        tyStr: []const u8,
        expected: []const []const u8,
    };

    var ZERO: usize = undefined;
    ZERO = 0;

    const types = [_]Pair{
        .{
            .tyStr = "U where U < Printable & String",
            .expected = ([_][]const u8{
                "String & Printable",
                "Printable & String",
            })[ZERO..],
        },
        // TODO: It's really questionable how they should be displayed
        // .{
        //     .tyStr = "IntEven -> U where U < Printable & Array<Int>",
        //     .expected = ([_][]const u8{
        //         // "IntEven -> U where U < Printable & Array<Int>",
        //     })[ZERO..],
        // },
        // .{
        //     .tyStr = "G<U> where U < Printalbe, G < Printable",
        //     .expected = ([_][]const u8{
        //         "U < Printalbe, G < Printable",
        //     })[ZERO..],
        // },
    };

    for (types) |pair| {
        const labelName = try getLabelName(pair.tyStr);

        var match = false;
        for (pair.expected) |oneOfExpected| {
            if (std.mem.eql(u8, oneOfExpected, labelName)) {
                match = true;
            }
        }

        if (!match) {
            std.debug.print("\nError: '{s}' not match one of expected\n", .{labelName});
            try std.testing.expect(false);
        }
    }
}
