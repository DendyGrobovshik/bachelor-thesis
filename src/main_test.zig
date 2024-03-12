const std = @import("std");
const query = @import("query.zig");

comptime {
    const test_files = [_]type{
        @import("tests/utils_test.zig"),
        @import("query.zig"),
    };
    for (test_files) |test_file| {
        std.testing.refAllDeclsRecursive(test_file);
    }
}
