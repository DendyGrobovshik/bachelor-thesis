const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Nominative = struct {
    name: []const u8,
    generic: ?*Type = null,

    pub fn format(
        this: Nominative,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{this.name});
        if (this.generic) |ty| {
            try writer.print("<{s}>", .{ty});
        }
    }
};

const List = struct {
    list: std.ArrayList(*Type),
    ordered: bool = false,

    pub fn format(
        this: List,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (this.ordered) try writer.print("(", .{}) else try writer.print("[", .{});

        const slice = this.list.items;
        if (slice.len > 0) {
            for (slice[0 .. slice.len - 1]) |item| {
                try writer.print("{s}, ", .{item});
            }
            try writer.print("{s}", .{slice[slice.len - 1]});
        }

        if (this.ordered) try writer.print(")", .{}) else try writer.print("]", .{});
    }
};

const Function = struct {
    from: *Type,
    to: *Type,
    directly: bool = true,

    pub fn format(
        this: Function,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s} -> ({s})", .{ this.from, this.to });
    }
};

const Kind = enum { nominative, list, function };

const Type = union(Kind) {
    nominative: Nominative,
    list: List,
    function: Function,

    pub fn format(
        this: Type,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try switch (this) {
            .nominative => writer.print("{s}", .{this.nominative}),
            .list => writer.print("{s}", .{this.list}),
            .function => writer.print("{s}", .{this.function}),
        };
    }
};

const Constraint = struct {
    type: *Type,
    superTypes: std.ArrayList(Type),

    pub fn format(
        this: Constraint,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        // TODO: print array with "&": https://stackoverflow.com/questions/77290888/can-i-sprintf-to-an-arraylist-in-zig
        try writer.print("{s} < {any}", .{ this.type, this.superTypes });
    }
};

const Question = struct {
    ty: *Type,
    constraints: std.ArrayList(Constraint),

    pub fn format(
        this: Question,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{this.ty});
        if (this.constraints.items.len > 0) {
            try writer.print(" where {any}", .{this.constraints});
        }
    }
};

pub const ParserError = error{
    UnclosedAngleBracket,
    UnclosedParentheses,
    UnexpectedNominative,
    UnexpectedArrow,
    UnexpectedChar,
    UnexpectedEnd,
} || std.mem.Allocator.Error;

pub fn Parser() type {
    const TokenKind = enum {
        char,
        name,
        arrow,
        end,
    };

    const Token = union(TokenKind) {
        char: u8,
        name: []const u8,
        arrow: bool,
        end: void,
    };

    return struct {
        const END: u8 = 3; // ASCII End-of-Text character
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        pos: usize,
        str: []const u8,

        pub fn init(allocator: Allocator, str: []const u8) !Self {
            const arena = std.heap.ArenaAllocator.init(allocator);

            var strWithEnd: []u8 = try allocator.alloc(u8, str.len + 1);
            std.mem.copyForwards(u8, strWithEnd[0..str.len], str);
            strWithEnd[str.len] = END;

            const parser = Self{
                .arena = arena,
                .str = strWithEnd,
                .pos = 0,
            };

            return parser;
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn parse(self: *Self) ParserError!*Type {
            std.debug.print("Parsing {s} ... {}\n", .{ self.str, self.pos });

            const baseType = try self.parseEndType();

            const nextToken = self.next();
            std.debug.print("Parsing continuation... {}\n", .{nextToken});
            switch (nextToken) {
                Token.arrow => {
                    const cont = try self.parse();
                    const ty = try self.arena.allocator().create(Type);
                    ty.function = .{ .from = baseType, .to = cont, .directly = nextToken.arrow };
                    return ty;
                },
                Token.char => {
                    if (nextToken.char != ',' and nextToken.char != ')' and nextToken.char != '>') {
                        return ParserError.UnexpectedChar;
                    }

                    if (nextToken.char == ')') {
                        self.pos -= 1;
                        return baseType;
                    }

                    var types = std.ArrayList(*Type).init(self.arena.allocator());
                    var ordered = false;
                    try types.append(baseType);

                    if (nextToken.char == ',') {
                        const conts = try self.parse();
                        switch (conts.*) {
                            .list => {
                                if (conts.list.ordered) {
                                    try types.append(conts);
                                } else {
                                    try types.appendSlice(conts.list.list.items);
                                }
                            },
                            .function => {
                                try types.append(conts.function.from);
                                ordered = false;

                                const ty = try self.arena.allocator().create(Type);
                                const from = try self.arena.allocator().create(Type);
                                from.* = .{ .list = .{ .list = types, .ordered = ordered } };
                                ty.function = .{ .from = from, .to = conts.function.to, .directly = conts.function.directly };
                                return ty;
                            },
                            .nominative => {
                                try types.append(conts);
                            },
                        }
                    } else {
                        self.pos -= 1;
                    }

                    const ty = try self.arena.allocator().create(Type);
                    ty.* = .{ .list = .{ .list = types, .ordered = ordered } };
                    return ty;
                },
                Token.end => return baseType,
                Token.name => return ParserError.UnexpectedNominative,
            }
        }

        fn parseEndType(self: *Self) ParserError!*Type {
            var nextToken = self.next();
            std.debug.print("Parsing end type... {}\n", .{nextToken});
            switch (nextToken) {
                .char => {
                    if (nextToken.char != '(') {
                        return ParserError.UnexpectedChar;
                    }
                    const ty = try self.parse();
                    switch (ty.*) {
                        .list => ty.list.ordered = true,
                        else => {},
                    }
                    nextToken = self.next();
                    if (nextToken.char != ')') {
                        return ParserError.UnexpectedChar;
                    }

                    return ty;
                },
                .name => {
                    const generic = try self.parseGeneric();
                    const ty = try self.arena.allocator().create(Type);
                    ty.* = .{ .nominative = .{ .name = nextToken.name, .generic = generic } };
                    return ty;
                },
                .arrow => return ParserError.UnexpectedArrow,
                .end => return ParserError.UnexpectedEnd,
            }
        }

        fn parseGeneric(self: *Self) ParserError!?*Type {
            var nextToken = self.next();
            std.debug.print("Parsing generic... {}\n", .{nextToken});
            switch (nextToken) {
                .char => {
                    if (nextToken.char != '<') {
                        self.pos -= 1;
                        return null;
                    }
                    const generic = try self.parse();
                    nextToken = self.next();
                    if (nextToken.char != '>') {
                        self.pos -= 1;
                        return null;
                    }

                    return generic;
                },
                .name => return ParserError.UnexpectedNominative,
                .arrow => {
                    self.pos -= 2;
                    return null;
                },
                .end => return null,
            }
        }

        inline fn cur(self: *Self) u8 {
            return self.str[self.pos];
        }

        inline fn next(self: *Self) Token {
            while (std.ascii.isWhitespace(self.cur())) {
                self.pos += 1;
            }

            var end = self.pos;
            while (std.ascii.isAlphabetic(self.str[end])) {
                end += 1;
            }
            if (self.pos != end) {
                const result = self.str[self.pos..end];
                self.pos = end;
                return .{ .name = result };
            }

            // NOTE: extract copypaste if 3 or more
            if ((self.cur() == '-') and (self.str[self.pos + 1] == '>')) {
                self.pos += 2;
                return .{ .arrow = true };
            }
            if ((self.cur() == '~') and (self.str[self.pos + 1] == '>')) {
                self.pos += 2;
                return .{ .arrow = false };
            }

            if (self.cur() != END) {
                self.pos += 1;
                return .{ .char = self.str[self.pos - 1] };
            }

            return .{ .end = {} };
        }
    };
}

test "simple type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B");
    defer parser.deinit();
    const actual: *Type = try parser.parse();

    var a: Type = .{ .nominative = .{ .name = "A" } };
    var b: Type = .{ .nominative = .{ .name = "B" } };

    const expected: *const Type = &.{ .function = .{
        .from = &a,
        .to = &b,
        .directly = true,
    } };

    try std.testing.expectEqualDeep(actual, expected);
}

test "simple type string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> (B)", actual);
}

test "function return tuple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> (C, D)");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> ((C, D))", actual);
}

test "different lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> C, B -> D");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> ([C, B] -> (D))", actual);
}

test "lons list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, B, C) -> A<A, B, C>");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, B, C) -> (A<[A, B, C]>)", actual);
}

test "list inside a list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, (A, B))");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, (A, B))", actual);
}

test "complicated type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A, B -> (A, B) -> A<T> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("[A, B] -> ((A, B) -> (A<[T]> -> (B -> ((C, D<[T]>)))))", actual);
}

test "complicated type 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> (A<T, G>) -> A, B -> A<T, (G, R)> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> (A<[T, G]> -> ([A, B] -> (A<[T, (G, R)]> -> (B -> ((C, D<[T]>))))))", actual);
}
