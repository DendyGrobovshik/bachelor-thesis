const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const common = @import("common.zig");
const queryParser = @import("../query_parser.zig");
const tree = @import("../engine/tree.zig");

const Tree = @import("../engine/tree.zig").Tree;
const Declaration = @import("../engine/entities.zig").Declaration;
const TypeNode = @import("../engine/TypeNode.zig");
const Message = common.Message;
const Status = common.Status;
const Hello = common.Hello;
const RawDeclaration = common.RawDeclaration;
const SubtypeQuestion = common.SubtypeQuestion;
const SubtypeAnswer = common.SubtypeAnswer;

pub const Server = struct {
    pub const Error = error{
        UnsupportedLanguge,
        StreamUnavailable,
        CanNotDetectJsonSize,
        UnsupportedOperation,
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

    pub fn initAndBind(allocator: Allocator) Error!*Server {
        const this = try allocator.create(Server);

        // TODO: debug only, remove
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

    fn nextMessage(self: *Server) Error![]const u8 {
        const readed = try self.stream.?.read(&self.buffer);

        std.debug.print("Server: got message '{s}'\n", .{self.buffer[0..readed]});
        return self.buffer[0..readed];
    }

    fn read(self: *Server, comptime T: type) Error!T {
        return try common.read(Server, self, T);
    }

    fn write(self: *Server, comptime T: type, payload: T) !void {
        try common.write(Server, self, T, payload);
    }

    pub fn awaitAndGreetClient(self: *Server) Error!void {
        const connection = try self.instance.accept();
        std.debug.print("Server: client({any}) connected\n", .{connection.address});

        self.stream = connection.stream;

        std.time.sleep(std.time.ns_per_ms * 20);

        const hello = try self.read(Hello);
        std.debug.print("Server: target language is '{s}'\n", .{hello.language});
    }

    fn parseRawDecl(self: *Server, rawDecl: RawDeclaration) Error!*Declaration {
        const name = try std.fmt.allocPrint(self.allocator, "{s}", .{rawDecl.name});
        const query = try queryParser.parseQuery(self.allocator, rawDecl.ty);

        var decl = try Declaration.init(self.allocator, name, query.ty);
        decl.id = rawDecl.index;

        return decl;
    }

    pub fn buildTree(self: *Server, t: *Tree) anyerror!void {
        std.debug.print("Server: start building tree...\n", .{});
        var timer = try std.time.Timer.start();

        while (true) {
            const rawDecl = try self.read(RawDeclaration);
            try t.addDeclaration(try self.parseRawDecl(rawDecl));

            _ = try self.write(Message, .{ .status = Status.finished });
            if (rawDecl.last) {
                break;
            }
        }

        std.debug.print("Server: tree builded in {}\n", .{std.fmt.fmtDuration(timer.read())});
    }

    pub fn askSubtype(self: *Server, parent: *TypeNode, child: *TypeNode) Error!bool {
        const question = .{ .question = SubtypeQuestion{
            .parent = try parent.name(),
            .child = try child.name(),
        } };

        try self.write(Message, question);

        const answer = (try self.read(SubtypeAnswer)).isChild;

        return answer;
    }

    pub fn getStream(self: *const Server) ?net.Stream {
        return self.stream;
    }
};
