const std = @import("std");

comptime {
    const test_files = [_]type{
        @import("tests/utils_test.zig"),
        @import("query_parser.zig"),
        @import("engine/tree.zig"),
        @import("engine/Node.zig"),
        @import("engine/TypeNode.zig"),
        @import("engine/tests/exact_search_tests.zig"),
        @import("engine/tests/node_labels_tests.zig"),
        @import("engine/tests/search_with_variance_test.zig"),
    };
    for (test_files) |test_file| {
        std.testing.refAllDeclsRecursive(test_file);
    }
}
