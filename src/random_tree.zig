const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const engineUtils = @import("engine/utils.zig");
const queryParser = @import("query_parser.zig");

const Tree = @import("engine/tree.zig").Tree;

// NOTE: quick-and-dirty, will be removed
pub const RandomTree = struct {
    allocator: Allocator,
    nominatives: std.ArrayList([]const u8),
    rnd: RndGen,
    subtypePairs: usize = 0,

    pub fn init(allocator: Allocator) Allocator.Error!*RandomTree {
        const self = try allocator.create(RandomTree);

        self.* = .{
            .allocator = allocator,
            .nominatives = std.ArrayList([]const u8).init(allocator),
            .rnd = RndGen.init(0),
        };

        return self;
    }

    pub fn randomName(self: *RandomTree) anyerror![]const u8 {
        var name = std.ArrayList(u8).init(self.allocator);

        for (0..self.rnd.random().intRangeLessThan(u3, 2, 3)) |_| {
            try name.append(self.rnd.random().intRangeLessThan(u8, 65, 85));
        }

        try self.nominatives.append(name.items);

        return name.items;
    }

    pub fn setSubtypingInfo(self: *RandomTree) !void {
        engineUtils.parentsOf = std.StringHashMap([]const []const u8).init(self.allocator);

        const n: usize = self.nominatives.items.len;
        std.debug.print("nominatives: {}\n", .{n});

        for (self.nominatives.items, 0..) |child, i| {
            var parentId = i;

            var parents = std.ArrayList([]const u8).init(self.allocator);
            while (true) {
                parentId += self.rnd.random().intRangeLessThan(usize, 1, @divTrunc(n, 10));
                if (parentId < n) {
                    try parents.append(self.nominatives.items[parentId]);
                } else {
                    break;
                }
            }
            try engineUtils.parentsOf.?.put(child, parents.items);
            self.subtypePairs += parents.items.len;
        }

        std.debug.print("Subtype pairs: {}\n", .{self.subtypePairs});
    }
};

pub fn randomTree(declCount: usize, nestedness: u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const PATH = "random_decls";
    const file = try std.fs.cwd().createFile(
        PATH,
        .{ .truncate = true },
    );
    defer file.close();

    const rt = try RandomTree.init(allocator);

    for (0..declCount) |i| {
        const typec = try queryParser.TypeC.generate(rt, nestedness);
        const tyStr = try std.fmt.allocPrint(allocator, "f{}: {s}\n", .{
            i,
            typec,
        });
        try file.writeAll(tyStr);
    }

    try rt.setSubtypingInfo();

    // Building tree
    var tree: *Tree = undefined;
    {
        var timer = try std.time.Timer.start();
        tree = try Tree.buildTreeFromFile(PATH, allocator);
        std.debug.print("Building tree: {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    // Extracting decls
    const decls = try tree.extractAllDecls(allocator);
    std.debug.assert(decls.count() == declCount);

    // Declaration type mean depth
    {
        var totalDepth: u32 = 0;

        var it = decls.keyIterator();
        while (it.next()) |decl| {
            const leaf = try tree.search(decl.*.ty, allocator);
            if (leaf) |leaf_| {
                totalDepth += leaf_.depth();
            }
        }

        // const meanTime = @divTrunc(timer.read(), decls.count());
        std.debug.print("Mean depth: {}\n", .{@divTrunc(totalDepth, decls.count())});
    }

    // Exact searching
    {
        var timer = try std.time.Timer.start();

        var it = decls.keyIterator();
        while (it.next()) |decl| {
            const leaf = try tree.search(decl.*.ty, allocator);
            std.debug.assert(leaf != null);
        }

        const meanTime = @divTrunc(timer.read(), decls.count());
        std.debug.print("Exact search mean time: {}\n", .{std.fmt.fmtDuration(meanTime)});
    }
}
