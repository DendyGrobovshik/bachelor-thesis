const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const common = @import("common.zig");
const queryParser = @import("../query_parser.zig");

const Tree = @import("../engine/tree.zig").Tree;
const Declaration = @import("../engine/entities.zig").Declaration;
const TypeNode = @import("../engine/TypeNode.zig");
const Variance = @import("../engine/variance.zig").Variance;
const EngineError = @import("../engine/error.zig").EngineError;
const Message = common.Message;
const Status = common.Status;
const Hello = common.Hello;
const RawDeclaration = common.RawDeclaration;
const SubtypeQuestion = common.SubtypeQuestion;
const Answer = common.Answer;

pub const Server = struct {
    pub const Error = error{
        CanNotDetectJsonSize,
        UnexpectedMessage,
    } || queryParser.Parser().Error || std.mem.Allocator.Error || std.posix.WriteError ||
        std.posix.ReadError || std.fmt.ParseIntError || std.posix.AcceptError ||
        std.net.Address.ListenError || std.json.ParseError(std.json.Scanner);

    pub const IP: [4]u8 = .{ 127, 0, 0, 1 };
    pub var PORT: u16 = 4000;

    pub const JSON_MAX_SIZE: usize = 6;

    instance: net.Server,
    allocator: Allocator,
    stream: net.Stream = undefined,

    buffer: [256]u8 = undefined,

    /// binds on port = 4000 + random(0, 100)
    /// with no fallback if ADDRINUSE
    pub fn initAndBind(allocator: Allocator) Error!*Server {
        const this = try allocator.create(Server);

        var gen = RndGen.init(@as(u64, @intCast(std.time.timestamp())));
        PORT = Server.PORT + gen.random().uintAtMost(u16, 100);

        const serverAddress = net.Address.initIp4(Server.IP, PORT);
        const serverOptions = net.Address.ListenOptions{};

        const instance = try serverAddress.listen(serverOptions);
        std.debug.print("Server: start listening at {any}...\n", .{instance.listen_address});

        this.* = .{
            .instance = instance,
            .allocator = allocator,
        };

        return this;
    }

    pub fn awaitAndGreetClient(self: *Server) Error!void {
        const connection = try self.instance.accept();
        std.debug.print("Server: client({any}) connected\n", .{connection.address});

        self.stream = connection.stream;

        std.time.sleep(std.time.ns_per_ms * 20);

        const clientMessage = try self.read(Message);

        switch (clientMessage) {
            .hello => std.debug.print("Server: target language is '{s}'\n", .{clientMessage.hello.language}),
            else => return Error.UnexpectedMessage,
        }
    }

    fn parseRawDecl(self: *Server, rawDecl: RawDeclaration) Error!*Declaration {
        const name = try std.fmt.allocPrint(self.allocator, "{s}", .{rawDecl.name});
        const query = try queryParser.parseQuery(self.allocator, rawDecl.ty);

        var decl = try Declaration.init(self.allocator, name, query.ty);
        decl.id = rawDecl.index;

        return decl;
    }

    /// awaitAndGreetClient must be invoked first
    pub fn buildTree(self: *Server, tree: *Tree) anyerror!void {
        std.debug.print("Server: start building tree...\n", .{});
        var timer = try std.time.Timer.start();

        while (true) {
            const message = try self.read(Message);
            switch (message) {
                .decl => try tree.addDeclaration(try self.parseRawDecl(message.decl)),
                .status => {
                    if (message.status == Status.finished) {
                        break;
                    }
                },
                else => return Error.UnexpectedMessage,
            }

            _ = try self.write(Message, .{ .status = Status.finished });
        }

        std.debug.print("Server: tree builded in {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    pub fn askSubtype(self: *Server, parent: *TypeNode, child: *TypeNode) Error!bool {
        const question = SubtypeQuestion{
            .parent = try parent.name(),
            .child = try child.name(),
        };

        try self.write(Message, Message{ .question = question });

        const message = try self.read(Message);

        switch (message) {
            .answer => return message.answer.is,
            else => return Error.UnexpectedMessage,
        }
    }

    pub fn answerQuestions(self: *Server, tree: *Tree) EngineError!void {
        while (true) {
            const message = try self.read(Message);

            switch (message) {
                .search => {
                    const query = try queryParser.parseQuery(self.allocator, message.search);
                    const candidates = try tree.findDeclarationsWithVariants(query.ty, Variance.covariant);
                    _ = try self.write(Message, .{ .status = Status.finished }); // finishing asking sutype questions

                    var declIds = std.ArrayList(usize).init(self.allocator);
                    for (candidates.items) |candidate| {
                        try declIds.append(candidate.id);
                    }

                    try self.write(Message, Message{ .decls = declIds.items });
                },
                .status => if (message.status == Status.finished) {
                    return;
                },
                else => return Error.UnexpectedMessage,
            }
        }
    }

    fn read(self: *Server, comptime T: type) Error!T {
        return try common.read(Server, self, T);
    }

    fn write(self: *Server, comptime T: type, payload: T) !void {
        try common.write(Server, self, T, payload);
    }
};