const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const query0 = @import("../query.zig");
const tree0 = @import("tree.zig");

const RawDecl = struct {
    ty: []const u8,
    name: []const u8,
};

pub fn buildTree(rawDecls: []const RawDecl, allocator: Allocator) !tree0.Tree {
    var tree = try tree0.Tree.init(allocator);

    for (rawDecls) |rawDecl| {
        const q = try tree0.parseQ(allocator, rawDecl.ty);

        const decl = try allocator.create(tree0.Declaration);
        decl.* = .{
            .name = rawDecl.name,
            .ty = q.ty,
        };

        try tree.addDeclaration(decl);
    }

    return tree;
}

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
        const query = try tree0.parseQ(allocator, rawDecl.ty);
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
        const query = try tree0.parseQ(allocator, rawDecl.ty);
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
        const query = try tree0.parseQ(allocator, rawDecl.ty);
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
        const query = try tree0.parseQ(allocator, rawDecl.ty);
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
        const query = try tree0.parseQ(allocator, rawDecl.ty);
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
        RawDecl{ .ty = "String -> String", .name = "boo" },
        RawDecl{ .ty = "String -> String", .name = "boo" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try tree0.parseQ(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        try std.testing.expectEqual(decls.items.len, 2);
    }
}

test "the types that were added to the tree are found by the exact query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const rawDecls = [_]RawDecl{
        RawDecl{ .ty = "Int -> Int", .name = "foo1" },
        RawDecl{ .ty = "String -> Int", .name = "foo2" },
        RawDecl{ .ty = "Array<Int> -> Int", .name = "foo3" },
        RawDecl{ .ty = "(Int -> String) -> Int -> String", .name = "foo4" },
        RawDecl{ .ty = "Int -> String -> Int -> String", .name = "foo5" },
        RawDecl{ .ty = "T -> T", .name = "foo6" },
        RawDecl{ .ty = "T -> G", .name = "foo7" },
        RawDecl{ .ty = "T where T < Printable & String", .name = "foo8" },
        RawDecl{ .ty = "IntEven -> T where T < Printable & Array<Int>", .name = "foo9" },
        RawDecl{ .ty = "G<T> where T < Printalbe, G < Printable", .name = "foo10" },
    };
    var searchIndex = try buildTree(&rawDecls, allocator);

    for (rawDecls) |rawDecl| {
        const query = try tree0.parseQ(allocator, rawDecl.ty);
        const decls = try searchIndex.findDeclarations(query.ty);

        // First declaration in result is exact match
        try std.testing.expectEqualStrings(rawDecl.name, decls.items[0].name);
    }
}
