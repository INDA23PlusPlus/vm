//!
//! VM program struct
//!

const Instruction = @import("instruction.zig");

const Self = @This();

code: []const Instruction,
entry: usize,
strings: []const []const u8,
field_names: []const []const u8,

pub fn init(code: []const Instruction, entry: usize, strings: []const []const u8, field_names: []const []const u8) Self {
    return .{ .code = code, .entry = entry, .strings = strings, .field_names = field_names };
}
