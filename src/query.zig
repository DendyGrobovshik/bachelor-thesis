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
        const arrow = if (this.directly) "->" else "~>";

        try writer.print("{s} {s} ({s})", .{ this.from, arrow, this.to });
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
    superTypes: std.ArrayList(*Type),

    pub fn format(
        this: Constraint,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        // TODO: print array with "&": https://stackoverflow.com/questions/77290888/can-i-sprintf-to-an-arraylist-in-zig

        const slice = this.superTypes.items;
        if (slice.len > 0) {
            try writer.print("{s} < ", .{this.type});
            for (slice[0 .. slice.len - 1]) |item| {
                try writer.print("{s} & ", .{item});
            }
            try writer.print("{s}", .{slice[slice.len - 1]});
        }
    }
};

const Query = struct {
    type: *Type,
    constraints: std.ArrayList(Constraint),

    pub fn format(
        this: Query,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const slice = this.constraints.items;
        if (slice.len > 0) {
            try writer.print("{s} where ", .{this.type});
            for (slice[0 .. slice.len - 1]) |item| {
                try writer.print("{s}, ", .{item});
            }
            try writer.print("{s}", .{slice[slice.len - 1]});
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
        str: []const u8,
        pos: usize,
        typeMap: std.StringHashMap(*Type),

        pub fn init(allocator: Allocator, str: []const u8) !Self {
            const arena = std.heap.ArenaAllocator.init(allocator);

            var strWithEnd: []u8 = try allocator.alloc(u8, str.len + 1);
            std.mem.copyForwards(u8, strWithEnd[0..str.len], str);
            strWithEnd[str.len] = END;

            if (std.mem.indexOf(u8, strWithEnd, "where")) |idx| {
                strWithEnd[idx] = END;
            }

            const parser = Self{
                .arena = arena,
                .str = strWithEnd,
                .pos = 0,
                .typeMap = std.StringHashMap(*Type).init(allocator),
            };

            return parser;
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        // Debug only
        pub fn printError(self: *Self, err: ParserError) void {
            std.debug.print("Error happend: {}\n", .{err});
            for (0..self.str.len - 1) |i| {
                const c = if (self.str[i] == END) 'w' else self.str[i];
                std.debug.print("{c}", .{c});
            }
            std.debug.print("\n", .{});

            for (0..self.pos - 1) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("^\n", .{});
        }

        pub fn parse(self: *Self) ParserError!Query {
            const ty = try parseType(self);

            var constraints: std.ArrayList(Constraint) = undefined;
            if (self.pos < self.str.len) {
                self.pos += 5; // (w)here -> (EOF)here, so skip 4 chars "here"
                constraints = try parseConstrants(self);
            } else {
                constraints = std.ArrayList(Constraint).init(self.arena.allocator());
            }

            return .{ .type = ty, .constraints = constraints };
        }

        pub fn parseType(self: *Self) ParserError!*Type {
            std.debug.print("Parsing {s} ... {}\n", .{ self.str, self.pos });

            const baseType = try self.parseEndType();

            const nextToken = self.next();
            std.debug.print("Parsing continuation... {}\n", .{nextToken});
            switch (nextToken) {
                Token.arrow => {
                    const cont = try self.parseType();
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
                        const conts = try self.parseType();
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
                    const ty = try self.parseType();
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
                    const allocator = self.arena.allocator();
                    const generic = try self.parseGeneric();
                    const ty = try allocator.create(Type);
                    ty.* = .{ .nominative = .{ .name = nextToken.name, .generic = generic } };

                    const typeStr = try std.fmt.allocPrint(allocator, "{}", .{ty});
                    if (self.typeMap.get(typeStr)) |savedTy| {
                        allocator.destroy(ty);
                        allocator.free(typeStr);
                        return savedTy;
                    } else {
                        try self.typeMap.put(typeStr, ty);
                        return ty;
                    }
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
                    // No space should be after '<' if it's begining of generic
                    if (self.cur() == ' ') {
                        self.pos -= 1;
                        return null;
                    }

                    const generic = try self.parseType();
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

        pub fn parseConstrants(self: *Self) ParserError!std.ArrayList(Constraint) {
            std.debug.print("Start parsrins constraints...\n", .{});
            var constraints = std.ArrayList(Constraint).init(self.arena.allocator());

            while (true) {
                const ty = try self.parseEndType();

                var nextToken = self.next();
                switch (nextToken) {
                    .char => {
                        if (nextToken.char != '<') {
                            return ParserError.UnexpectedChar;
                        }
                    },
                    .arrow => return ParserError.UnexpectedArrow,
                    .name => return ParserError.UnexpectedNominative,
                    .end => return ParserError.UnexpectedEnd,
                }
                var superTypes = std.ArrayList(*Type).init(self.arena.allocator());

                while (true) {
                    const superType = try self.parseEndType();
                    try superTypes.append(superType);

                    nextToken = self.next();
                    switch (nextToken) {
                        .end => {
                            break;
                        },
                        .char => {
                            switch (nextToken.char) {
                                ',' => {
                                    self.pos -= 1;
                                    break;
                                },
                                '&' => continue,
                                else => return ParserError.UnexpectedChar,
                            }
                        },
                        .name => return ParserError.UnexpectedNominative,
                        .arrow => return ParserError.UnexpectedArrow,
                    }
                }

                const constraint = .{ .type = ty, .superTypes = superTypes };
                try constraints.append(constraint);

                nextToken = self.next(); // ',' or EOF
                switch (nextToken) {
                    .end => break,
                    .char => {
                        if (nextToken.char == ',') {
                            continue;
                        }

                        return ParserError.UnexpectedChar;
                    },
                    .name => return ParserError.UnexpectedNominative,
                    .arrow => return ParserError.UnexpectedArrow,
                }
            }

            return constraints;
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

            // if (self.pos < self.str) {
            //     self.pos += 1;
            // }

            return .{ .end = {} };
        }
    };
}

test "simple type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B");
    defer parser.deinit();
    const actual: *Type = try parser.parseType();

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
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> (B)", actual);
}

test "function return tuple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> (C, D)");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> ((C, D))", actual);
}

test "different lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> C, B -> D");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> ([C, B] -> (D))", actual);
}

test "lons list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, B, C) -> A<A, B, C>");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, B, C) -> (A<[A, B, C]>)", actual);
}

test "list inside a list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, (A, B))");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, (A, B))", actual);
}

test "complicated type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A, B -> (A, B) -> A<T> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("[A, B] -> ((A, B) -> (A<[T]> -> (B -> ((C, D<[T]>)))))", actual);
}

test "complicated type 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> (A<T, G>) -> A, B -> A<T, (G, R)> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> (A<[T, G]> -> ([A, B] -> (A<[T, (G, R)]> -> (B -> ((C, D<[T]>))))))", actual);
}

test "complicated type with ~>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) ~> (A<T, G>) -> A, B -> A<T, (G ~> R)> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) ~> (A<[T, G]> -> ([A, B] -> (A<[T, G ~> (R)]> -> (B -> ((C, D<[T]>))))))", actual);
}

test "function in generic ~>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A<D, (A -> B ~> C), B>");
    defer parser.deinit();
    const ty: *Type = try parser.parseType();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A<[D, A -> (B ~> (C)), B]>", actual);
}

test "simple constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B<T> where T < ToString");
    defer parser.deinit();
    const ty: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> (B<[T]>) where T < ToString", actual);
}

test "complicated constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B<T> where T < ToString & B, A < X<T> & Y");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{query});

    try std.testing.expectEqualStrings("A -> (B<[T]>) where T < ToString & B, A < X<[T]> & Y", actual);
}

test "complicated constraint 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A<(A -> B, T)> where A < (A -> B) & (A, T)");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{query});

    try std.testing.expectEqualStrings("A<[A -> ([B, T])]> where A < A -> (B) & (A, T)", actual);
}

test "nominative with same name point to the same type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "T -> A<T> where T < A<T>");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const t1 = query.type.function.from;
    const t2 = query.type.function.to.nominative.generic.?.list.list.items[0];
    const t3 = query.constraints.items[0].type;
    const t4 = query.constraints.items[0].superTypes.items[0].nominative.generic.?.list.list.items[0];

    try std.testing.expectEqual(t1, t2);
    try std.testing.expectEqual(t1, t3);
    try std.testing.expectEqual(t1, t4);
}
