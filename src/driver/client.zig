const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const server = @import("server.zig");
const common = @import("common.zig");
const utils = @import("../engine/utils.zig");

const Server = @import("server.zig").Server;
const TypeNode = @import("../engine/TypeNode.zig");
const Message = common.Message;
const Status = common.Status;
const Hello = common.Hello;
const RawDeclaration = common.RawDeclaration;
const SubtypeQuestion = common.SubtypeQuestion;
const Answer = common.Answer;

const DECLARATIONS = [_]RawDeclaration{
    .{ .name = "transform", .ty = "(Int -> String) -> Int -> String" },
    .{ .name = "transform2", .ty = "Int -> String -> Int -> String" },
    .{ .name = "generic1", .ty = "T -> T" },
    .{ .name = "generic2", .ty = "T -> G" },
    .{ .name = "constraints", .ty = "T where T < Printable & String" },
    .{ .name = "twocons", .ty = "IntEven -> T where T < Printable & Array<Int>" },
    .{ .name = "what", .ty = "G<T> where T < Printalbe, G < Printable" },
    .{ .name = "w2", .ty = "Array<String> -> Array<Int>" },
    .{ .name = "zz", .ty = "Array<Array<T>>" },
    .{ .name = "zztop", .ty = "Int -> Array<Array<T>>" },
    .{ .name = "gg", .ty = "HashMap<Int, String> -> Int" },
    .{ .name = "x", .ty = "Array<Int>" },
    .{ .name = "y", .ty = "Array<Int>" },
    .{ .name = "pair", .ty = "(String, Int)" },
    .{ .name = "get", .ty = "Int, Array<T> -> T" },
    .{ .name = "firstCommon", .ty = "Array<T>, Array<T> -> T" },
    .{ .name = "threeParam", .ty = "Ab, Bc, Cd -> Ok" },
    .{ .name = "unitIn", .ty = "() -> Inta" },
    .{ .name = "withUnit2", .ty = "() -> (() -> Int)" },
    .{ .name = "withUnit3", .ty = "() -> (Int -> ())" },
    .{ .name = "fgen", .ty = "Array<Int -> String>" },
};

const QUESTIONS = [_][]const u8{
    "Int -> Array<Array<T>>",
    "T where T < Printable & String",
    "Array<Int>",
};

pub const Client = struct {
    allocator: Allocator,
    stream: net.Stream,

    pub fn sleepAndRun(allocator: Allocator) !void {
        std.time.sleep(10 * std.time.ns_per_ms);

        const client = try Client.initAndConnect(allocator);
        try client.run();
    }

    pub fn initAndConnect(allocator: Allocator) !*Client {
        const this = try allocator.create(Client);

        const serverAddress = net.Address.initIp4(Server.IP, Server.PORT);
        std.debug.print("Client: connecting to server({any})...\n", .{serverAddress});
        const stream = try net.tcpConnectToAddress(serverAddress);

        std.debug.print("Client: connected to server({any})\n", .{serverAddress});

        this.* = .{
            .allocator = allocator,
            .stream = stream,
        };

        return this;
    }

    pub fn run(self: *Client) Server.Error!void {
        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();

        const helloMessage = Message{ .hello = Hello{ .language = "abstractlanguage" } };

        try self.write(Message, helloMessage);

        try self.sendDeclarations();
        try self.askQuestions();
    }

    fn sendDeclarations(self: *Client) Server.Error!void {
        for (DECLARATIONS, 0..) |rawDecl_, index| {
            const rawDecl = RawDeclaration{
                .name = rawDecl_.name,
                .ty = rawDecl_.ty,
                .index = index,
            };
            try self.write(Message, Message{ .decl = rawDecl });

            try self.answerSubtypeQuestions();
        }

        try self.write(Message, Message{ .status = Status.finished });
    }

    fn answerSubtypeQuestions(self: *Client) Server.Error!void {
        while (true) {
            const serverMessage = try self.read(Message);

            switch (serverMessage) {
                .question => {
                    const answer = Answer{
                        .is = utils.defaultSubtype(serverMessage.question.parent, serverMessage.question.child),
                    };
                    const message = Message{ .answer = answer };
                    _ = try self.write(Message, message);
                },
                .status => {
                    if (serverMessage.status == Status.finished) {
                        break;
                    }
                },
                else => return Server.Error.UnexpectedMessage,
            }
        }
    }

    fn askQuestions(self: *Client) Server.Error!void {
        for (QUESTIONS) |ty| {
            try self.write(Message, Message{ .search = ty });

            try self.answerSubtypeQuestions();

            const serverMessage = try self.read(Message);
            switch (serverMessage) {
                .decls => {
                    std.debug.print("QUESTION: '{s}', ", .{ty});
                    std.debug.print("ANSWER: [", .{});
                    for (serverMessage.decls, 0..) |declId, i| {
                        const decl = DECLARATIONS[declId];
                        std.debug.print("'{s}'", .{decl.name});
                        if (i != serverMessage.decls.len - 1) {
                            std.debug.print(", ", .{});
                        }
                    }
                    std.debug.print("]\n", .{});
                },
                else => return Server.Error.UnexpectedMessage,
            }
        }

        try self.write(Message, Message{ .status = Status.finished });
    }

    fn write(self: *Client, comptime T: type, payload: T) Server.Error!void {
        try common.write(Client, self, T, payload);
    }

    fn read(self: *Client, comptime T: type) !T {
        return try common.read(Client, self, T);
    }
};
