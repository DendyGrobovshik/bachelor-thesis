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
    .{ .name = "constraints2", .ty = "T where T < Int & String" },
    .{ .name = "complex", .ty = "SubOfThree" },
    .{ .name = "constraints2", .ty = "T where T < Printable & String & IntEven" },
    .{ .name = "twocons", .ty = "IntEven -> T where T < Printable & Array<Int>" },
    .{ .name = "what", .ty = "G<T> where T < Printable, G < Printable" },
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
    .{ .name = "T_AnBn", .ty = "Stub -> T where T < An & Bn" },
    .{ .name = "T_AnCn", .ty = "Stub -> T where T < Cn & An" },
    .{ .name = "T_CnDn", .ty = "Stub -> T where T < Cn & Dn" },
    .{ .name = "AnDn", .ty = "Stub -> AnDn" },
    .{ .name = "T_AnDn", .ty = "Stub -> T where T < An & Dn" },
    .{ .name = "AnBnCn", .ty = "Stub -> nBnCn" },
    .{ .name = "T_AnBnCn", .ty = "Stub -> T where T < An & Bn & Cn" },
    .{ .name = "T_CnT_AnDn", .ty = "Stub -> T where T < AnDn & Cn" },
    .{ .name = "T_AnCnDn", .ty = "Stub -> T where T < An & Cn & Dn" },
    .{ .name = "Yn", .ty = "Stub -> Yn" },
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

        std.debug.print("Client: handle({})\n", .{stream.handle});
        try common.NO_DELAY(stream);

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
        var rawDecls = std.ArrayList(RawDeclaration).init(self.allocator);
        for (DECLARATIONS, 0..) |rawDecl_, index| {
            const rawDecl = RawDeclaration{
                .name = rawDecl_.name,
                .ty = rawDecl_.ty,
                .index = index,
            };

            try rawDecls.append(rawDecl);
        }
        try self.write(Message, Message{ .insertMany = rawDecls.items });

        try self.answerSubtypeQuestions();

        try self.write(Message, Message{ .status = Status.finished });
    }

    fn answerSubtypeQuestions(self: *Client) Server.Error!void {
        while (true) {
            const serverMessage = try self.read(Message);

            switch (serverMessage) {
                .subtype => {
                    const answer = Answer{
                        .is = utils.defaultSubtype(
                            serverMessage.subtype.parent,
                            serverMessage.subtype.child,
                        ),
                    };
                    const message = Message{ .answer = answer };
                    _ = try self.write(Message, message);
                },
                .whoAreTheParentsOf => {
                    const parents = try utils.getParentsOfType(serverMessage.whoAreTheParentsOf);

                    _ = try self.write(Message, Message{ .theParentsAre = parents });
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
                .declIds => {
                    std.debug.print("QUESTION: '{s}', ", .{ty});
                    std.debug.print("ANSWER: [", .{});
                    for (serverMessage.declIds, 0..) |declId, i| {
                        const decl = DECLARATIONS[declId];
                        std.debug.print("'{s}'", .{decl.name});
                        if (i != serverMessage.declIds.len - 1) {
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
