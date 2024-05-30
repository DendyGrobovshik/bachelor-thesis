const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const queryParser = @import("../../query_parser.zig");

const Tree = @import("../tree.zig").Tree;
const Declaration = @import("../entities.zig").Declaration;
const AutoHashSet = @import("../utils.zig").AutoHashSet;

pub const RawDecl = struct {
    ty: []const u8,
    name: []const u8,
};

pub fn buildTree(rawDecls: []const RawDecl, allocator: Allocator) !*Tree {
    var tree = try Tree.init(allocator);

    for (rawDecls) |rawDecl| {
        const q = try queryParser.parseQuery(allocator, rawDecl.ty);

        const decl = try allocator.create(Declaration);
        decl.* = .{
            .name = rawDecl.name,
            .ty = q.ty,
        };

        try tree.addDeclaration(decl);
    }

    return tree;
}

pub fn inDecls(name: []const u8, decls: AutoHashSet(*Declaration)) bool {
    var in = false;
    var declsIt = decls.keyIterator();
    while (declsIt.next()) |decl| {
        if (std.mem.eql(u8, decl.*.name, name)) {
            in = true;
        }
    }
    return in;
}
