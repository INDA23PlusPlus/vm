//!
//! VM program struct
//!

const VMInstruction = @import("VMInstruction.zig");

const Self = @This();

code: []const VMInstruction,
entry: usize,

pub fn init(code: []const VMInstruction, entry: usize) Self {
    return .{ .code = code, .entry = entry };
}
