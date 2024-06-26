const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const Server = @import("server.zig").Server;
const ServerError = Server.Error;

pub const Hello = struct {
    language: []const u8,
    // TODO: variance setting
};

pub const RawDeclaration = struct {
    index: usize = 0,
    name: []const u8,
    ty: []const u8,

    pub fn format(
        this: RawDeclaration,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}: {s}", .{ this.name, this.ty });
    }
};

pub const SubtypeQuestion = struct {
    parent: []const u8,
    child: []const u8,
};

pub const Answer = struct {
    is: bool,
};

pub const Status = enum {
    finished,
};

pub const MessageKind = enum {
    hello,
    subtype,
    insert,
    insertMany,
    answer,
    status,
    search,
    declIds,
    whoAreTheParentsOf,
    theParentsAre,
};

pub const Message = union(MessageKind) {
    hello: Hello,
    subtype: SubtypeQuestion,
    insert: RawDeclaration,
    insertMany: []const RawDeclaration,
    answer: Answer,
    status: Status,
    search: []const u8,
    declIds: []const usize,
    whoAreTheParentsOf: []const u8,
    theParentsAre: []const []const u8,
};

// TODO: free memory
pub inline fn write(comptime This: type, self: *This, comptime T: type, payload: T) ServerError!void {
    const json = try std.json.stringifyAlloc(self.allocator, payload, .{});

    var message = try self.allocator.alloc(u8, json.len + Server.JSON_MAX_SIZE);

    var countStr: [Server.JSON_MAX_SIZE]u8 = .{ 0, 0, 0, 0, 0, 0 };
    _ = try std.fmt.bufPrint(&countStr, "{:0>6}", .{json.len});

    std.mem.copyForwards(u8, message[0..Server.JSON_MAX_SIZE], &countStr);
    std.mem.copyForwards(u8, message[Server.JSON_MAX_SIZE..], json);

    _ = try self.stream.write(message);
}

// TODO: free memory
pub inline fn read(comptime This: type, self: *This, comptime T: type) ServerError!T {
    var buffer: [Server.JSON_MAX_SIZE]u8 = undefined;
    {
        const readed = try self.stream.readAtLeast(&buffer, Server.JSON_MAX_SIZE);
        if (readed != Server.JSON_MAX_SIZE) {
            return ServerError.CanNotDetectJsonSize;
        }
    }

    const jsonLength = try std.fmt.parseInt(usize, &buffer, 10);
    // std.debug.print("JSON LENGTH: {}\n", .{jsonLength});

    var json = try self.allocator.alloc(u8, jsonLength);

    var readed: usize = 0;
    while (readed < jsonLength) {
        readed = readed + try self.stream.read(json[readed..]);
    }

    // std.debug.print("JSON: '{s}'\n", .{json});

    const parsed = try std.json.parseFromSlice(
        T,
        self.allocator,
        json,
        .{},
    );
    // defer parsed.deinit(); TODO: not working in case of []RawDeclarations

    return parsed.value;
}

pub fn NO_DELAY(stream: net.Stream) !void {
    const TCP_NODELAY = 0x01;
    try std.posix.setsockopt(
        stream.handle,
        std.posix.IPPROTO.TCP,
        TCP_NODELAY,
        &std.mem.toBytes(@as(c_int, 1)),
    );
}
