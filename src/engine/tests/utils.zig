const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const tree0 = @import("../tree.zig");

pub const RawDecl = struct {
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
