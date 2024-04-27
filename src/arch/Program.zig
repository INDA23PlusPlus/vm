//!
//! Program struct
//!

const Instruction = @import("Instruction.zig");
const Allocator = @import("std").mem.Allocator;

const Self = @This();

code: []const Instruction,
entry: usize,
strings: []const []const u8,
field_names: []const []const u8,
tokens: []const []const u8,
// This field is used if a program is constructed from
// Asm.zig or binary.zig.
deinit_data: ?struct {
    allocator: Allocator,
    strings: []const u8,
    field_names: []const u8,
    source: []const u8,
} = null,

pub fn init(code: []const Instruction, entry: usize, strings: []const []const u8, field_names: []const []const u8) Self {
    return .{ .code = code, .entry = entry, .strings = strings, .field_names = field_names };
}

pub fn deinit(self: *Self) void {
    if (self.deinit_data) |data| {
        data.allocator.free(self.strings);
        data.allocator.free(self.field_names);
        data.allocator.free(self.tokens);
        data.allocator.free(self.code);
        data.allocator.free(data.strings);
        data.allocator.free(data.field_names);
        data.allocator.free(data.source);
    }
}
