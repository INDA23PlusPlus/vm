//!
//! Architectural type definitions.
//!

const std = @import("std");

pub const Type = enum(u8) {
    // zig fmt: off
    unit       = 0b11111111,

    int        = 0b00000001,
    float      = 0b00000011,

    string_ref = 0b00000100,
    string_lit = 0b00001100,

    list       = 0b00010000,

    object     = 0b00100000,
    // zig fmt: on

    fn isValid(x: Type) bool {
        inline for (std.meta.fields(Type)) |field| {
            if (field.value == @intFromEnum(x)) {
                return true;
            }
        }
        return false;
    }

    fn assertValid(x: Type) void {
        std.debug.assert(x.isValid());
    }

    pub fn isValidComparison(lhs: Type, rhs: Type) bool {
        lhs.assertValid();
        rhs.assertValid();
        return @intFromEnum(lhs) & @intFromEnum(rhs) > 0;
    }

    /// equivalent to `(x == .string_lit or x == .string_ref)`
    pub fn isString(x: Type) bool {
        x.assertValid();
        return @intFromEnum(x) | 0b00001000 == 0b00001100;
    }

    /// equivalent to `(lhs.isString() and rhs.isString())`
    pub fn areBothStrings(lhs: Type, rhs: Type) bool {
        lhs.assertValid();
        rhs.assertValid();
        return @intFromEnum(lhs) | @intFromEnum(rhs) | 0b00001000 == 0b00001100;
    }

    /// equivalent to `(x == .int or x == .float)`
    pub fn isNumeric(x: Type) bool {
        x.assertValid();
        return @intFromEnum(x) | 0b00000010 == 0b00000011;
    }

    /// equivalent to `(lhs.isNumeric() and rhs.isNumeric())`
    pub fn areBothNumeric(lhs: Type, rhs: Type) bool {
        lhs.assertValid();
        rhs.assertValid();
        return @intFromEnum(lhs) | @intFromEnum(rhs) | 0b00000010 == 0b00000011;
    }

    /// equivalent to `(areBothNumeric(lhs, rhs) and lhs != rhs)`
    pub fn areDifferentNumeric(lhs: Type, rhs: Type) bool {
        lhs.assertValid();
        rhs.assertValid();
        return @intFromEnum(lhs) ^ @intFromEnum(rhs) == 0b00000010;
    }

    pub fn str(t: Type) []const u8 {
        return switch (t) {
            .int => "integer",
            .object => "struct",
            else => @tagName(t),
        };
    }
};

comptime {
    @setEvalBranchQuota(2000);
    for ([_]Type{
        .int,
        .float,
        .unit,
        .string_ref,
        .string_lit,
        .list,
        .object,
    }) |e1| {
        e1.assertValid();

        std.debug.assert(e1.isString() == (e1 == .string_lit or e1 == .string_ref));
        std.debug.assert(e1.isNumeric() == (e1 == .int or e1 == .float));

        for ([_]Type{
            .int,
            .float,
            .unit,
            .string_ref,
            .string_lit,
            .list,
            .object,
        }) |e2| {
            e2.assertValid();

            const int_float = (e1 == .int and e2 == .float) or (e1 == .float and e2 == .int);
            const string_string = (e1 == .string_ref and e2 == .string_lit) or (e1 == .string_lit and e2 == .string_ref);
            const unit_any = e1 == .unit or e2 == .unit;

            std.debug.assert(Type.isValidComparison(e1, e2) == (e1 == e2 or int_float or string_string or unit_any));
            std.debug.assert(Type.areBothStrings(e1, e2) == (e1.isString() and e2.isString()));
            std.debug.assert(Type.areBothNumeric(e1, e2) == (e1.isNumeric() and e2.isNumeric()));
            std.debug.assert(Type.areDifferentNumeric(e1, e2) == (e1.isNumeric() and e2.isNumeric() and e1 != e2));
        }
    }
}
