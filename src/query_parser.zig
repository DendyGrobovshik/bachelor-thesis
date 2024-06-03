const std = @import("std");
const Allocator = @import("std").mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const TypeNode = @import("engine/TypeNode.zig");
const utils = @import("utils.zig");
const main = @import("main.zig");

/// parse `str` according to query_grammar.txt
pub fn parseQuery(allocator: Allocator, str: []const u8) Parser().Error!Query {
    var parser = try Parser().init(allocator, str);
    defer parser.deinit();

    const query = parser.parse() catch |err| {
        parser.printError(err);
        return err;
    };

    // std.debug.print("Query parsed: {}\n", .{query});

    return query;
}

const Nominative = struct {
    name: []const u8,
    generic: ?*TypeC = null,
    hadGeneric: bool = false,

    // It is always null for concrete types.
    // For generic type(which is current one-caps letter):
    // it updated only once when this node for the first time inserted in tree
    // if this generic will inserted in future, than in `following(to, backlink)`
    // `backlink` will be updated to this `typeNode`, so `A -> A` and `A -> B`
    // can be easily distinshed, because of in second case typeNode will be `null`
    // So, this with fact that equally named nominative types are points to the same `*Nomintive`
    typeNode: ?*TypeNode = null,

    pub fn init(name: []const u8, generic: ?*TypeC, allocator: Allocator) !*Type {
        const ty = try allocator.create(Type);

        ty.* = .{ .nominative = .{
            .name = name,
            .generic = generic,
        } };

        return ty;
    }

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

    // TODO: kind of hack: now support only one-caps generic
    // it can be extended in reverse way, need to keep only alphabet size array
    // no need to keep all the names definied in all packages
    pub fn isGeneric(self: *Nominative) bool {
        if (self.name.len == 1 and std.ascii.isUpper(self.name[0])) {
            return true;
        }
        return false;
    }

    pub fn generate(allocator: Allocator) anyerror!Nominative {
        // std.debug.print("generating nominative\n", .{});
        const name = try utils.randomName(allocator);
        var generic: ?*TypeC = null;
        if (main.rnd.random().int(u3) < 3) {
            const typec = try allocator.create(TypeC);
            // const list = try allocator.create(Type);
            // list.* = .{ .list = try utils.generateGeneric(allocator) };
            const ty = try allocator.create(Type);

            var gname = std.ArrayList(u8).init(allocator);
            try gname.append(main.rnd.random().intRangeLessThan(u8, 65, 90));

            ty.* = .{
                .nominative = Nominative{
                    .name = gname.items,
                },
            };

            typec.* = .{
                .ty = ty,
                .constraints = std.ArrayList(Constraint).init(allocator),
            };
            generic = typec;
        }

        return Nominative{
            .name = name,
            .generic = generic,
        };
    }
};

pub const List = struct {
    list: std.ArrayList(*TypeC),
    ordered: bool = false,

    pub fn init(allocator: Allocator, types: std.ArrayList(*TypeC)) !*TypeC {
        const typec = try allocator.create(TypeC);
        const ty = try allocator.create(Type);

        ty.* = .{
            .list = List{
                .list = types,
            },
        };

        typec.* = .{
            .ty = ty,
            .constraints = std.ArrayList(Constraint).init(allocator),
        };

        return typec;
    }

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

pub const Function = struct {
    from: *TypeC,
    to: *TypeC,
    directly: bool = true,
    braced: bool = false,

    pub fn init(allocator: Allocator, from: *TypeC, to: *TypeC, directly: bool) !*TypeC {
        const typec = try allocator.create(TypeC);
        const ty = try allocator.create(Type);

        ty.* = .{
            .function = Function{
                .from = from,
                .to = to,
                .directly = directly,
            },
        };

        typec.* = .{
            .ty = ty,
            .constraints = std.ArrayList(Constraint).init(allocator),
        };

        return typec;
    }

    pub fn format(
        this: Function,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const arrow = if (this.directly) "->" else "~>";

        switch (this.from.ty.*) {
            .function => try writer.print("({s})", .{this.from.ty}),
            else => try writer.print("{s}", .{this.from.ty}),
        }

        try writer.print(" {s} ", .{arrow});

        switch (this.to.ty.*) {
            .function => try writer.print("({s})", .{this.to.ty}),
            else => try writer.print("{s}", .{this.to.ty}),
        }
    }

    pub fn generate(allocator: Allocator) anyerror!Function {
        // std.debug.print("generating function\n", .{});
        return Function{
            .from = try TypeC.generate(allocator),
            .to = try TypeC.generate(allocator),
        };
    }
};

const Kind = enum { nominative, list, function };

pub const Type = union(Kind) {
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

    pub fn generate(allocator: Allocator) anyerror!*Type {
        const self = try allocator.create(Type);

        switch (main.rnd.random().int(u2)) {
            0 => self.* = .{ .function = try Function.generate(allocator) },
            else => self.* = .{ .nominative = try Nominative.generate(allocator) },
        }

        return self;
    }
};

// Type with contraints
pub const TypeC = struct {
    ty: *Type,
    constraints: std.ArrayList(Constraint),
    default: bool = false,

    pub fn init(allocator: Allocator, ty: *Type) !*TypeC {
        const constraints = std.ArrayList(Constraint).init(allocator);
        const self = try allocator.create(TypeC);

        self.* = .{
            .ty = ty,
            .constraints = constraints,
        };

        return self;
    }

    pub inline fn isFunction(self: *TypeC) bool {
        return switch (self.ty.kind) {
            .function => true,
            else => false,
        };
    }

    pub fn format(
        this: TypeC,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{this.ty});
    }

    pub fn collectConstraints(self: *TypeC, allocator: Allocator) !std.ArrayList(*TypeC) {
        var result = std.ArrayList(*TypeC).init(allocator);

        if (self.constraints.items.len > 0) {
            try result.append(self);
        }

        switch (self.ty.*) {
            .function => {
                try result.appendSlice((try self.ty.function.from.collectConstraints(allocator)).items);
                try result.appendSlice((try self.ty.function.to.collectConstraints(allocator)).items);
            },
            .nominative => {
                if (self.ty.nominative.generic) |generic| {
                    try result.appendSlice((try generic.collectConstraints(allocator)).items);
                }
            },
            .list => {
                for (self.ty.list.list.items) |typec| {
                    try result.appendSlice((try typec.collectConstraints(allocator)).items);
                }
            },
        }

        return result;
    }

    pub fn constraintsText(self: *TypeC, allocator: Allocator) ![]const u8 {
        var result = try std.fmt.allocPrint(allocator, "{s}", .{self.constraints.items[0]});

        for (self.constraints.items[1..]) |constraint| {
            result = try std.fmt.allocPrint(allocator, "{s} & {s}", .{ result, constraint });
        }

        return result;
    }

    pub fn generate(allocator: Allocator) anyerror!*TypeC {
        // std.debug.print("generating typec\n", .{});
        return TypeC.init(allocator, try Type.generate(allocator));
    }
};

pub const Constraint = struct {
    ty: *TypeC,
    superTypes: std.ArrayList(*TypeC),

    pub fn format(
        this: Constraint,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const slice = this.superTypes.items;
        if (slice.len > 0) {
            try writer.print("{s} < ", .{this.ty});
            for (slice[0 .. slice.len - 1]) |item| {
                try writer.print("{s} & ", .{item});
            }
            try writer.print("{s}", .{slice[slice.len - 1]});
        }
    }
};

pub const Query = struct {
    ty: *TypeC,
    constraints: std.ArrayList(Constraint),

    pub fn format(
        this: Query,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const slice = this.constraints.items;
        if (slice.len > 0) {
            try writer.print("{s} where ", .{this.ty});
            for (slice[0 .. slice.len - 1]) |item| {
                try writer.print("{s}, ", .{item});
            }
            try writer.print("{s}", .{slice[slice.len - 1]});
        } else {
            try writer.print("{d}", .{this.ty});
        }
    }
};

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
        pub const Error = error{
            UnclosedAngleBracket,
            UnclosedParentheses,
            UnexpectedNominative,
            UnexpectedArrow,
            UnexpectedChar,
            UnexpectedEnd,
        } || std.mem.Allocator.Error;

        const END: u8 = 3; // ASCII End-of-Text character
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        str: []const u8,
        pos: usize,
        typeMap: std.StringHashMap(*TypeC),

        pub fn init(allocator: Allocator, str: []const u8) !Self {
            const arena = std.heap.ArenaAllocator.init(allocator);

            var strWithEnd: []u8 = try allocator.alloc(u8, str.len + 1);
            std.mem.copyForwards(u8, strWithEnd[0..str.len], str);
            strWithEnd[str.len] = END;

            // `T where T < G` updated to `T ␃here T < G`
            // beacuse parsing has two stages
            if (std.mem.indexOf(u8, strWithEnd, "where")) |idx| {
                strWithEnd[idx] = END;
            }

            const parser = Self{
                .arena = arena,
                .str = strWithEnd,
                .pos = 0,
                .typeMap = std.StringHashMap(*TypeC).init(allocator),
            };

            return parser;
        }

        pub fn deinit(self: *Self) void {
            // self.arena.deinit();
            self.typeMap.deinit();
        }

        pub fn printError(self: *Self, err: Parser().Error) void {
            std.debug.print("Error happend: {} when parsing '{s}'\n", .{
                err,
                self.str,
            });
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

        pub fn parse(self: *Self) Parser().Error!Query {
            const ty = try parseType(self);

            var constraints: std.ArrayList(Constraint) = undefined;
            self.pos += 1;
            if (self.pos < self.str.len) {
                self.pos += 4; // (w)here -> (EOF)here, so skip 4 chars "here"
                constraints = try parseConstraints(self);
            } else {
                constraints = std.ArrayList(Constraint).init(undefined);
            }

            // assigning constraints to types
            for (constraints.items) |constraint| {
                // only constraints for nominative currently supported
                if (self.typeMap.get(constraint.ty.ty.nominative.name)) |typec| {
                    try typec.constraints.append(constraint);
                }
            }

            return .{
                .ty = ty,
                .constraints = constraints,
            };
        }

        pub fn parseType(self: *Self) Parser().Error!*TypeC {
            // std.debug.print("query_parsed.parseType {s} ... {}\n", .{ self.str, self.pos });
            const allocator = self.arena.allocator();

            const baseType = try self.parseEndType();

            const nextToken = self.next();
            switch (nextToken) {
                Token.arrow => {
                    return Function.init(allocator, baseType, try self.parseType(), nextToken.arrow);
                },
                Token.char => {
                    if (nextToken.char != ',' and nextToken.char != ')' and nextToken.char != '>') {
                        return Parser().Error.UnexpectedChar;
                    }

                    if (nextToken.char == ')') {
                        self.pos -= 1;
                        return baseType;
                    }
                    if (nextToken.char == '>') {
                        self.pos -= 1;
                        return baseType;
                    }

                    var types = std.ArrayList(*TypeC).init(allocator);
                    try types.append(baseType);

                    if (nextToken.char == ',') {
                        const conts = try self.parseType();
                        switch (conts.ty.*) {
                            .list => {
                                if (conts.ty.list.ordered) {
                                    try types.append(conts);
                                } else {
                                    try types.appendSlice(conts.ty.list.list.items);
                                }
                            },
                            .function => {
                                if (conts.ty.function.braced) {
                                    try types.append(conts);
                                } else {
                                    switch (conts.ty.function.from.ty.*) {
                                        .list => {
                                            if (conts.ty.function.from.ty.list.ordered) {
                                                try types.append(conts.ty.function.from);
                                            } else {
                                                // TODO: free memory
                                                try types.appendSlice(conts.ty.function.from.ty.list.list.items);
                                            }
                                        },
                                        else => try types.append(conts.ty.function.from),
                                    }

                                    return Function.init(
                                        allocator,
                                        try List.init(allocator, types),
                                        conts.ty.function.to,
                                        conts.ty.function.directly,
                                    );
                                }
                            },
                            .nominative => {
                                try types.append(conts);
                            },
                        }
                    } else {
                        self.pos -= 1;
                    }

                    return List.init(allocator, types);
                },
                Token.end => return baseType,
                Token.name => return Parser().Error.UnexpectedNominative,
            }
        }

        fn parseEndType(self: *Self) Parser().Error!*TypeC {
            // std.debug.print("Parsing end type... {}\n", .{nextToken});
            const allocator = self.arena.allocator();

            var nextToken = self.next();
            switch (nextToken) {
                .char => {
                    if (nextToken.char == '!') {
                        var typec = try self.parseEndType();
                        typec.default = true;
                        return typec;
                    }

                    if (nextToken.char != '(') {
                        return Parser().Error.UnexpectedChar;
                    }
                    nextToken = self.next();
                    switch (nextToken) {
                        .char => if (nextToken.char == ')') {
                            const empty = std.ArrayList(*TypeC).init(undefined);

                            // empty tuple ~ void ~ unit
                            const emptyTuple = try List.init(allocator, empty);
                            // it's always ordered bacuse it's a tuple, not an unorded list of params
                            emptyTuple.ty.list.ordered = true;
                            return emptyTuple;
                        } else {
                            self.pos -= 1;
                        },
                        .name => {
                            self.pos -= nextToken.name.len;
                        },
                        .arrow => return Parser().Error.UnexpectedArrow,
                        .end => return Parser().Error.UnexpectedEnd,
                    }

                    const ty = try self.parseType();
                    switch (ty.ty.*) {
                        .list => ty.ty.list.ordered = true,
                        .function => ty.ty.function.braced = true,
                        else => {},
                    }
                    nextToken = self.next();
                    if (nextToken.char != ')') {
                        return Parser().Error.UnexpectedChar;
                    }

                    return ty;
                },
                .name => {
                    const generic = try self.parseGeneric();

                    const ty = try Nominative.init(nextToken.name, generic, allocator);

                    const typeStr = try std.fmt.allocPrint(allocator, "{}", .{ty});
                    if (self.typeMap.get(typeStr)) |savedTy| {
                        allocator.destroy(ty);
                        allocator.free(typeStr);
                        return savedTy;
                    } else {
                        const res = try wrapInTypeC(ty, allocator);
                        try self.typeMap.put(typeStr, res);
                        return res;
                    }
                },
                .arrow => return Parser().Error.UnexpectedArrow,
                .end => return Parser().Error.UnexpectedEnd,
            }
        }

        fn parseGeneric(self: *Self) Parser().Error!?*TypeC {
            var nextToken = self.next();

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
                        return Parser().Error.UnclosedAngleBracket;
                    }

                    return try unwrapGeneric(generic);
                },
                .name => return Parser().Error.UnexpectedNominative,
                .arrow => {
                    self.pos -= 2;
                    return null;
                },
                .end => return null,
            }
        }

        // TODO: free memory
        pub fn unwrapGeneric(generic: *TypeC) Parser().Error!*TypeC {
            switch (generic.ty.*) {
                .list => {
                    if (generic.ty.list.list.items.len == 1) {
                        return generic.ty.list.list.items[0];
                    }

                    generic.ty.list.ordered = true;
                },
                else => {},
            }

            return generic;
        }

        pub fn parseConstraints(self: *Self) Parser().Error!std.ArrayList(Constraint) {
            // std.debug.print("Start parsrins constraints...\n", .{});
            const allocator = self.arena.allocator();

            var constraints = std.ArrayList(Constraint).init(allocator);

            while (true) {
                const ty = try self.parseEndType();

                var nextToken = self.next();
                switch (nextToken) {
                    .char => {
                        if (nextToken.char != '<') {
                            return Parser().Error.UnexpectedChar;
                        }
                    },
                    .arrow => return Parser().Error.UnexpectedArrow,
                    .name => return Parser().Error.UnexpectedNominative,
                    .end => return Parser().Error.UnexpectedEnd,
                }
                var superTypes = std.ArrayList(*TypeC).init(allocator);

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
                                else => return Parser().Error.UnexpectedChar,
                            }
                        },
                        .name => return Parser().Error.UnexpectedNominative,
                        .arrow => return Parser().Error.UnexpectedArrow,
                    }
                }

                const constraint = .{ .ty = ty, .superTypes = superTypes };
                try constraints.append(constraint);

                nextToken = self.next(); // ',' or EOF
                switch (nextToken) {
                    .end => break,
                    .char => {
                        if (nextToken.char == ',') {
                            continue;
                        }

                        return Parser().Error.UnexpectedChar;
                    },
                    .name => return Parser().Error.UnexpectedNominative,
                    .arrow => return Parser().Error.UnexpectedArrow,
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

            if (self.cur() == '!') {
                self.pos += 1;
                return .{ .char = '!' };
            }

            var end = self.pos;
            while (std.ascii.isAlphabetic(self.str[end]) or
                self.str[end] == '.' or
                self.str[end] == '_' or
                self.str[end] == '$' or // TODO: '$' allowed on any position
                std.ascii.isDigit(self.str[end]))
            { // '.' is part of fq name
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

fn wrapInTypeC(ty: *Type, allocator: Allocator) !*TypeC {
    const typec = try allocator.create(TypeC);
    typec.* = .{
        .ty = ty,
        .constraints = std.ArrayList(Constraint).init(allocator),
    };

    return typec;
}

test "simple type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B");
    defer parser.deinit();
    const actual: *Type = (try parser.parseType()).ty;

    const a = Type{ .nominative = .{ .name = "A" } };
    const b = Type{ .nominative = .{ .name = "B" } };

    try std.testing.expectEqualDeep(actual.function.from.ty.*, a);
    try std.testing.expectEqualDeep(actual.function.to.ty.*, b);
}

test "simple type string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> B", actual);
}

test "function return tuple" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> (C, D)");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> (C, D)", actual);
}

test "different lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> C, B -> D");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> ([C, B] -> D)", actual);
}

test "function argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A -> B) -> A -> B");
    defer parser.deinit();
    const ty: *Type = (try parser.parse()).ty.ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A -> B) -> (A -> B)", actual);
}

test "lons list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, B, C) -> A<A, B, C>");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, B, C) -> A<(A, B, C)>", actual);
}

test "list inside a list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(A, (A, B))");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("(A, (A, B))", actual);
}

test "long unordered list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "Ab, Bc, Cd -> Ok");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{query});

    try std.testing.expectEqualStrings("[Ab, Bc, Cd] -> Ok", actual);
}

test "comma mixed with arrows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "(R -> G), E -> E, (R -> G)");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("[R -> G, E] -> [E, R -> G]", actual);
}

test "comma mixed with arrows 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A, B -> C, D ~> E, (R -> G)");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("[A, B] -> ([C, D] ~> [E, R -> G])", actual);
}

test "complicated type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A, B -> (A, B) -> A<T> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("[A, B] -> ((A, B) -> (A<T> -> (B -> (C, D<T>))))", actual);
}

test "complicated type 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) -> (A<T, G>) -> A, B -> A<T, (G, R)> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) -> (A<(T, G)> -> ([A, B] -> (A<(T, (G, R))> -> (B -> (C, D<T>)))))", actual);
}

test "complicated type with ~>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "((A, B), C) ~> (A<T, G>) -> A, B -> A<T, (G ~> R)> -> (B -> (C, D<T>))");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("((A, B), C) ~> (A<(T, G)> -> ([A, B] -> (A<(T, G ~> R)> -> (B -> (C, D<T>)))))", actual);
}

test "function in generic ~>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A<D, (A -> B ~> C), B>");
    defer parser.deinit();
    const ty: *Type = (try parser.parseType()).ty;

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A<(D, A -> (B ~> C), B)>", actual);
}

test "simple constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B<T> where T < ToString");
    defer parser.deinit();
    const ty: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{ty});

    try std.testing.expectEqualStrings("A -> B<T> where T < ToString", actual);
}

test "complicated constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A -> B<T> where T < ToString & B, A < X<T> & Y");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{query});

    try std.testing.expectEqualStrings("A -> B<T> where T < ToString & B, A < X<T> & Y", actual);
}

test "complicated constraint 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "A<(A -> B, T)> where A < (A -> B) & (A, T)");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const actual = try std.fmt.allocPrint(arena.allocator(), "{}", .{query});

    try std.testing.expectEqualStrings("A<A -> [B, T]> where A < A -> B & (A, T)", actual);
}

test "nominative with same name point to the same type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "T -> A<T> where T < A<T>");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const t1 = query.ty.ty.function.from.ty;
    const t2 = query.ty.ty.function.to.ty.nominative.generic.?.ty;
    const t3 = query.constraints.items[0].ty.ty;
    const t4 = query.constraints.items[0].superTypes.items[0].ty.nominative.generic.?.ty;

    try std.testing.expectEqual(t1, t2);
    try std.testing.expectEqual(t1, t3);
    try std.testing.expectEqual(t1, t4);
}

test "type with default" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "!ToString -> A");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const t1 = query.ty.ty.function.from;
    const t2 = query.ty.ty.function.to;

    try std.testing.expect(t1.default);
    try std.testing.expect(!t2.default);
}

// TODO: check properly: `!ToString, !(A -> B) -> (A, !B) -> A`
test "type with default 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser().init(arena.allocator(), "!ToString, !(A -> B) -> A");
    defer parser.deinit();
    const query: Query = try parser.parse();

    const t1 = query.ty.ty.function.from;
    const t2 = t1.ty.list.list.items[0];
    const t3 = t1.ty.list.list.items[1];

    try std.testing.expect(!t1.default);
    try std.testing.expect(t2.default);
    try std.testing.expect(t3.default);
}
