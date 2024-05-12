//!
//! Architectural type definitions.
//!

pub const Type = enum(u8) {
    // zig fmt: off
    unit       = 0b00010,

    int        = 0b00000,
    float      = 0b00001,

    string     = 0b10000,

    list       = 0b01010,
    object     = 0b01100,
    // zig fmt: on

    pub fn str(t: Type) []const u8 {
        return switch (t) {
            .int => "integer",
            .object => "struct",
            else => @tagName(t),
        };
    }
};
