const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;
const Mutex = std.Thread.Mutex;

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

const QUESTIONS = [_][]const u8{
    // "Int -> Array<Array<T>>",
    // "T where T < Printable & String",
    // "Array<Int>",
};

pub const KotlinClient = struct {
    allocator: Allocator,
    stream: net.Stream,
    DECLS: std.ArrayList(RawDeclaration),
    results: std.ArrayList(u8),
    mutex: Mutex,

    pub fn sleepAndRun(allocator: Allocator) !void {
        std.time.sleep(10 * std.time.ns_per_ms);

        const client = try KotlinClient.initAndConnect(allocator);
        try client.run();
    }

    pub fn initAndConnect(allocator: Allocator) !*KotlinClient {
        const this = try allocator.create(KotlinClient);

        const serverAddress = net.Address.initIp4(Server.IP, Server.PORT);
        std.debug.print("Client: connecting to server({any})...\n", .{serverAddress});
        const stream = try net.tcpConnectToAddress(serverAddress);

        std.debug.print("Client: handle({})\n", .{stream.handle});
        try common.NO_DELAY(stream);

        std.debug.print("Client: connected to server({any})\n", .{serverAddress});

        this.* = .{
            .allocator = allocator,
            .stream = stream,
            .DECLS = try KotlinClient.readDeclsFromFile(allocator),
            .results = std.ArrayList(u8).init(allocator),
            .mutex = Mutex{},
        };

        return this;
    }

    pub fn run(self: *KotlinClient) Server.Error!void {
        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();

        const helloMessage = Message{ .hello = Hello{ .language = "abstractlanguage" } };

        try self.write(Message, helloMessage);

        try self.sendDeclarations();
        try self.askQuestions();
    }

    fn sendDeclarations(self: *KotlinClient) Server.Error!void {
        var rawDecls = std.ArrayList(RawDeclaration).init(self.allocator);
        for (self.DECLS.items, 0..) |rawDecl_, index| {
            const rawDecl = RawDeclaration{
                .name = rawDecl_.name,
                .ty = rawDecl_.ty,
                .index = index,
            };
            std.debug.print("{s}\n", .{rawDecl});

            try rawDecls.append(rawDecl);
        }
        try self.write(Message, Message{ .insertMany = rawDecls.items });

        try self.answerSubtypeQuestions();

        try self.write(Message, Message{ .status = Status.finished });
    }

    fn answerSubtypeQuestions(self: *KotlinClient) Server.Error!void {
        while (true) {
            const serverMessage = try self.read(Message);

            switch (serverMessage) {
                .subtype => {
                    const answer = Answer{
                        .is = try compiles(self, "hello.kt", serverMessage.subtype.child, serverMessage.subtype.parent),
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

    fn compiles(self: *KotlinClient, path: []const u8, candidateTy: []const u8, queryTy: []const u8) Server.Error!bool {
        const template = "fun <T> foo(): Boolean {s}\nval candidate: {s} = throw NotImplementedError()\nval query: {s} = candidate{s}\n";
        const code = try std.fmt.allocPrint(self.allocator, template, .{
            "{",
            candidateTy,
            queryTy,
            "}",
        });

        const file = try std.fs.cwd().createFile(
            path,
            .{ .truncate = true },
        );
        defer file.close();
        try file.writeAll(code);

        const compile = try std.ChildProcess.run(.{
            .allocator = self.allocator,
            .argv = &.{ "kotlinc", path },
        });

        switch (compile.term) {
            .Exited => if (compile.term.Exited != 0) {
                // std.debug.print("Compiler stderr: '{s}'\n", .{compile.stderr});
                if (std.mem.count(u8, compile.stderr, "type argument") > 0) {
                    return Server.Error.CanNotCheckSubtyping;
                }

                if (std.mem.count(u8, compile.stderr, "initializer type mismatch") > 0) {
                    return false;
                }

                if (std.mem.count(u8, compile.stderr, "unresolved reference") > 0) {
                    return Server.Error.CanNotCheckSubtyping;
                }

                return Server.Error.CanNotCheckSubtyping;
            } else {
                return true;
            },
            else => return Server.Error.CanNotCheckSubtyping,
        }
    }

    fn askQuestions(self: *KotlinClient) Server.Error!void {
        const CHECKS = 2;
        var handles: [CHECKS]std.Thread = undefined;

        for (0..CHECKS) |i| {
            std.debug.print("STARTING {} asker\n", .{i});
            const handle = try std.Thread.spawn(.{}, askQuestion, .{ self, i });

            handles[i] = handle;
        }

        for (handles) |handle| {
            handle.join();
        }

        try self.write(Message, Message{ .status = Status.finished });
        std.debug.print("RESULTS:\n {s}\n", .{self.results.items});
    }

    fn askQuestion(self: *KotlinClient, threadId: usize) !void {
        const path = try std.fmt.allocPrint(self.allocator, "hello{}.kt", .{threadId});

        var gen = RndGen.init(@as(u64, @intCast(std.time.timestamp())));

        const queryId = gen.random().intRangeAtMost(usize, 0, self.DECLS.items.len - 1);
        const ty = self.DECLS.items[queryId].ty;

        try self.write(Message, Message{ .search = ty });

        try self.answerSubtypeQuestions();

        const serverMessage = try self.read(Message);
        switch (serverMessage) {
            .declIds => {
                std.debug.print("QUESTION: '{s}', ", .{ty});
                std.debug.print("ANSWER: [", .{});
                for (serverMessage.declIds, 0..) |declId, i| {
                    const decl = self.DECLS.items[declId];
                    std.debug.print("'{s}'", .{decl.name});
                    if (i != serverMessage.declIds.len - 1) {
                        std.debug.print(", ", .{});
                    }
                }
                std.debug.print("]\n", .{});

                std.debug.print("START VALIDATION\n", .{});
                const result = try self.validateAnswer(path, ty, serverMessage.declIds);
                try self.results.appendSlice(result);
            },
            else => return Server.Error.UnexpectedMessage,
        }
    }

    fn validateAnswer(self: *KotlinClient, path: []const u8, query: []const u8, answerIds: []const usize) ![]const u8 {
        var errors: i32 = 0;

        for (0..self.DECLS.items.len) |i| {
            var shouldCompiles = false;
            for (answerIds) |id| {
                if (id == i) {
                    shouldCompiles = true;
                }
            }
            const decl = self.DECLS.items[i];
            const status = self.compiles(path, decl.ty, query) catch cerr: {
                break :cerr false;
            };
            if (status != shouldCompiles) {
                errors = errors + 1;
                std.debug.print("ERRROR: query='{s}', decl '{s}': '{s}' = {}\n", .{ query, decl.name, decl.ty, status });
            }
        }

        const result = try std.fmt.allocPrint(self.allocator, "VALIDATIONG ERRORS: [{}/{}]\n", .{ errors, self.DECLS.items.len });
        std.debug.print("{s}", .{result});

        return result;
    }

    fn write(self: *KotlinClient, comptime T: type, payload: T) Server.Error!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try common.write(KotlinClient, self, T, payload);
    }

    fn read(self: *KotlinClient, comptime T: type) !T {
        self.mutex.lock();
        defer self.mutex.unlock();
        return try common.read(KotlinClient, self, T);
    }

    fn readDeclsFromFile(allocator: Allocator) !std.ArrayList(RawDeclaration) {
        var result = std.ArrayList(RawDeclaration).init(allocator);

        const file = try std.fs.cwd().openFile(
            "./kotlin_driver/declarations.txt",
            .{},
        );
        defer file.close();

        var bufReader = std.io.bufferedReader(file.reader());
        var inStream = bufReader.reader();

        var buf: [1024]u8 = undefined;
        while (try inStream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (!std.mem.containsAtLeast(u8, line, 1, ":")) {
                continue;
            }

            var it = std.mem.split(u8, line, ":");

            var declId: usize = 0;
            if (std.mem.containsAtLeast(u8, line, 2, ":")) {
                declId = try std.fmt.parseInt(usize, it.next().?, 10);
            }

            const name = try std.fmt.allocPrint(allocator, "{s}", .{
                std.mem.trim(u8, it.next().?, " "),
            });
            const ty = try std.fmt.allocPrint(allocator, "{s}", .{it.next().?});

            try result.append(RawDeclaration{ .name = name, .ty = ty });
        }

        return result;
    }
};
