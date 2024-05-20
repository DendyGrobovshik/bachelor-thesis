const std = @import("std");

pub const Variance = enum {
    invariant,
    covariant,
    contravariant,
    bivariant,

    pub fn format(
        this: Variance,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try switch (this) {
            .invariant => writer.print("invariant", .{}),
            .covariant => writer.print("covariant", .{}),
            .contravariant => writer.print("contravariant", .{}),
            .bivariant => writer.print("bivariant", .{}),
        };
    }

    fn inverse(self: Variance) Variance {
        return switch (self) {
            .invariant => Variance.invariant,
            .covariant => Variance.contravariant,
            .contravariant => Variance.covariant,
            .bivariant => Variance.bivariant,
        };
    }

    // commutative, associative
    pub fn x(self: Variance, other: Variance) Variance {
        return switch (self) {
            .invariant => Variance.invariant,
            .covariant => other,
            .contravariant => other.inverse(),
            .bivariant => switch (other) {
                .invariant => Variance.invariant,
                else => Variance.bivariant,
            },
        };
    }
};

pub const VarianceConfig = struct {
    functionIn: Variance,
    functionOut: Variance,
    nominativeGeneric: Variance,
    tupleVariance: Variance,
};

pub const defaultVariances = .{
    .functionIn = Variance.contravariant,
    .functionOut = Variance.covariant,
    .nominativeGeneric = Variance.invariant,
    .tupleVariance = Variance.covariant,
};
