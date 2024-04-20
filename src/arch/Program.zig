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

// Used to deallocate program constructed from Asm.zig.
// If memory is managed externally, this can be left as null.
deinit_data: ?struct {
    allocator: Allocator,
    // Contiguos buffers that slices in `strings` and `field_names` point to.
    strings: []const u8,
    field_names: []const u8,
} = null,

pub fn init(code: []const Instruction, entry: usize, strings: []const []const u8, field_names: []const []const u8) Self {
    return .{ .code = code, .entry = entry, .strings = strings, .field_names = field_names };
}

pub fn deinit(self: *Self) void {
    if (self.deinit_data) |data| {
        data.allocator.free(self.strings);
        data.allocator.free(self.field_names);
        data.allocator.free(self.code);
        data.allocator.free(data.strings);
        data.allocator.free(data.field_names);
    }
}
