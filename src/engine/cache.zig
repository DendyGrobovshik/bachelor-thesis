const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Node = @import("Node.zig");
const TypeNode = @import("TypeNode.zig");
const constants = @import("constants.zig");
const main = @import("../main.zig");

pub var cache: Cache = undefined;

pub const Cache = struct {
    const Child = struct {
        name: []const u8,
        is: bool,
    };

    head: *Node,
    // arena: std.heap.ArenaAllocator,
    allocator: Allocator,
    childsOf: std.StringHashMap(std.ArrayList(Child)),

    pub fn init(allocator: Allocator) !Cache {
        // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        // const allocator = arena.allocator();

        const head = try Node.init(allocator, &constants.PREROOT);

        const childsOf = std.StringHashMap(std.ArrayList(Child)).init(allocator);

        return .{
            .head = head,
            // .arena = arena,
            .allocator = allocator,
            .childsOf = childsOf,
        };
    }

    fn calculate(parent: *TypeNode, child: *TypeNode) !bool {
        const Pair = struct { []const u8, []const u8 };

        const pairs = [_]Pair{
            .{ "Collection", "String" },
            .{ "Int", "IntEven" },
            .{ "Printable", "IntEven" },
            .{ "Printable", "Collection" },
        };

        for (pairs) |pair| {
            if (std.mem.eql(u8, try parent.name(), pair[0]) and std.mem.eql(u8, try child.name(), pair[1])) {
                return true;
            }
        }

        return false;
    }
};

// TODO: move out, design driver for target language
pub fn greater(parent: *TypeNode, child: *TypeNode) !bool {
    const parentName = try parent.name();
    const childName = try child.name();

    if (parent.isUniversal()) {
        return true;
    }

    if (std.mem.eql(u8, parentName, childName)) {
        return true;
    }

    // return Cache.calculate(parent, child);

    if (cache.childsOf.getPtr(parentName)) |childs| {
        for (childs.items) |childCandidate| {
            if (std.mem.eql(u8, childCandidate.name, childName)) {
                // std.debug.print("cached 1: parent='{s}' child='{s} is {}'\n", .{
                //     parentName,
                //     childName,
                //     childCandidate.is,
                // });
                return childCandidate.is;
            }
        }

        const isParent = try Cache.calculate(parent, child);
        try childs.append(.{ .name = childName, .is = isParent });
        // std.debug.print("cached 2: parent='{s}' child='{s} is {}'\n", .{
        //     parentName,
        //     childName,
        //     isParent,
        // });
        return isParent;
    } else {
        var childs = std.ArrayList(Cache.Child).init(cache.allocator);
        const isParent = try Cache.calculate(parent, child);
        try childs.append(.{ .name = childName, .is = isParent });

        // std.debug.print("cahced 3: parent='{s}' child='{s}' is {}\n", .{
        //     parentName,
        //     childName,
        //     isParent,
        // });

        try cache.childsOf.put(parentName, childs);

        return isParent;
    }

    unreachable;
}
