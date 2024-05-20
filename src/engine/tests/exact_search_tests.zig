const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const buildTree = @import("utils.zig").buildTree;
const queryParser = @import("../../query_parser.zig");

const RawDecl = @import("utils.zig").RawDecl;

// NOTE: All the tests the file are about exact search(no variance or inheritance)

test "higher order functions are not mixed with common" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "(Int -> String) -> Bool", .name = "hof" },
        RawDecl{ .ty = "Int -> String -> Bool", .name = "nohof" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "generics differs with different arguments differs" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "T -> G", .name = "foo" },
        RawDecl{ .ty = "T -> T", .name = "boo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "nominative with concrete differs from nominative with generic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Array<T>", .name = "foo" },
        RawDecl{ .ty = "Array<Int>", .name = "boo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "concrete type and constraint with this type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Printable", .name = "foo" },
        RawDecl{ .ty = "T where T < Printable", .name = "boo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "naminative with and without generic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Array", .name = "foo" },
        RawDecl{ .ty = "Array<T>", .name = "boo" },
        RawDecl{ .ty = "Array<Int>", .name = "goo" },
        RawDecl{ .ty = "Array<T> where T < Printable", .name = "doo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "two with same type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int -> String", .name = "foo" },
        RawDecl{ .ty = "Int -> String", .name = "boo" },
        RawDecl{ .ty = "String -> String", .name = "goo" },
        RawDecl{ .ty = "String -> String", .name = "doo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 2);
    }
}

test "finding lists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "HashMap<K, V>", .name = "foo1" },
        RawDecl{ .ty = "HashkMap<K, V> -> HashMap<K, V>", .name = "foo2" },
        RawDecl{ .ty = "(Int, String)", .name = "foo3" },
        RawDecl{ .ty = "Int -> (Int, (String, Bool))", .name = "foo4" },
        RawDecl{ .ty = "HashMap<(Int, String), Bool>", .name = "foo5" },
        RawDecl{ .ty = "HashMap<(Int, Array<T>), HashMap<K, String>>", .name = "foo5" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(decls.getLast().name, rawDecl.name);
    }
}

test "unorded lists lists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int, Array<T> -> T", .name = "foo1" },
        RawDecl{ .ty = "Array<T>, Array<T> -> T", .name = "foo2" },
        RawDecl{ .ty = "Ab, Bc, Cd -> Ok", .name = "foo2" },
        RawDecl{ .ty = "Ab, (Bc, Cd) -> Ok", .name = "foo2" },
        RawDecl{ .ty = "Int, String, Array<(Int, String2)> -> Ok", .name = "foo3" },
        RawDecl{ .ty = "(Ab, Bc), Cd, (De -> Eg), Gh<T> -> Ok", .name = "foo4" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 1);
        try std.testing.expectEqualStrings(decls.getLast().name, rawDecl.name);
    }
}

test "the types that were added to the tree are found by the exact query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int -> Int", .name = "foo1" },
        RawDecl{ .ty = "String -> Int", .name = "foo2" },
        RawDecl{ .ty = "(String, Int)", .name = "foo2" },
        RawDecl{ .ty = "Array<Int> -> Int", .name = "foo3" },
        RawDecl{ .ty = "(Int -> String) -> Int -> String", .name = "foo4" },
        RawDecl{ .ty = "Int -> String -> Int -> String", .name = "foo5" },
        RawDecl{ .ty = "T -> T", .name = "foo6" },
        RawDecl{ .ty = "T -> G", .name = "foo7" },
        RawDecl{ .ty = "T where T < Printable & String", .name = "foo8" },
        RawDecl{ .ty = "IntEven -> T where T < Printable & Array<Int>", .name = "foo9" },
        RawDecl{ .ty = "G<T> where T < Printalbe, G < Printable", .name = "foo10" },
        RawDecl{ .ty = "HashMap<K, V>", .name = "foo11" },
        RawDecl{ .ty = "HashkMap<K, V> -> HashMap<K, V>", .name = "foo12" },
        RawDecl{ .ty = "(Int, String)", .name = "foo13" },
        RawDecl{ .ty = "Int -> (Int, (String, Bool))", .name = "foo14" },
        RawDecl{ .ty = "HashMap<(Int, String), Bool>", .name = "foo15" },
        RawDecl{ .ty = "HashMap<(Int, Array<T>), HashMap<K, String>>", .name = "foo16" },
        RawDecl{ .ty = "Int, Array<T> -> T", .name = "foo17" },
        RawDecl{ .ty = "Array2<T>, Int -> T", .name = "foo18" },
        RawDecl{ .ty = "() -> Int", .name = "foo19" },
        RawDecl{ .ty = "() -> (() -> Int)", .name = "foo20" },
        RawDecl{ .ty = "() -> (Int -> ())", .name = "foo21" },
        RawDecl{ .ty = "Array<Int -> String>", .name = "foo22" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try queryParser.parseQuery(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        // First declaration in result is exact match
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}

test "function with unordered parameters is found where query is ordered" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int, String -> Bool", .name = "foo1" },
        RawDecl{ .ty = "String, Int -> Bool", .name = "foo2" },
        RawDecl{ .ty = "String -> Int -> Bool", .name = "boo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    const query = try queryParser.parseQuery(allocator, "String -> Int -> Bool");
    const decls = try searchIndex.findDeclarations(query.ty);

    try std.testing.expectEqual(3, decls.items.len);

    for (rawDecls) |rawDecl| {
        var found = false;

        for (decls.items) |foundDecl| {
            if (std.mem.eql(u8, foundDecl.name, rawDecl.name)) {
                found = true;
            }
        }

        if (!found) {
            try std.testing.expectEqualStrings("The declararation was not found!!!", rawDecl.name);
        }
    }
}
