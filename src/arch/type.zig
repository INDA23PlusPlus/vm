//!
//! Architectural type definitions.
//!

pub const Type = enum(u8) {
    // zig fmt: off
    unit       = 0b111111,

    int        = 0b000001,
    float      = 0b000011,

    string_ref = 0b000100,
    string_lit = 0b001100,

    list       = 0b010000,

    object     = 0b100000,
    // zig fmt: on

    pub fn validComparison(lhs: Type, rhs: Type) bool {
        return @intFromEnum(lhs) & @intFromEnum(rhs) > 0;
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
    for ([_]Type{
        .int,
        .float,
        .unit,
        .string_ref,
        .string_lit,
        .list,
        .object,
    }) |e1| {
        for ([_]Type{
            .int,
            .float,
            .unit,
            .string_ref,
            .string_lit,
            .list,
            .object,
        }) |e2| {
            if (e1.validComparison(e2)) {
                // only valid if one is int and one is float, both are some kind of string, or either is unit
                if (e1 != e2) {
                    const int_float = (e1 == .int and e2 == .float) or (e1 == .float and e2 == .int);
                    const string_string = (e1 == .string_ref and e2 == .string_lit) or (e1 == .string_lit and e2 == .string_ref);
                    const one_is_unit = e1 == .unit or e2 == .unit;
                    if (!int_float and !string_string and !one_is_unit) {
                        @compileError("type comparisons are broken!");
                    }
                }
            }
        }
    }
}
