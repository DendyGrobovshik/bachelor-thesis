const std = @import("std");

pub const EngineError = error{
    NotYetSupported,
    ShouldBeUnreachable,
} || std.mem.Allocator.Error;
