//!
//! VM program struct
//!

const VMInstruction = @import("VMInstruction.zig");

const Self = @This();

code: []const VMInstruction,
entry: usize,
strings: []const []const u8,

pub fn init(code: []const VMInstruction, entry: usize, strings: []const []const u8) Self {
    return .{ .code = code, .entry = entry, .strings = strings };
}
