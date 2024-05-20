const std = @import("std");

const server = @import("../driver/server.zig");

pub const EngineError = error{
    NotYetSupported,
    ShouldBeUnreachable,
} || std.mem.Allocator.Error || std.posix.ReadError || std.posix.WriteError || server.Server.Error;
