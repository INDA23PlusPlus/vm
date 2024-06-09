//!
//! Program struct
//!

const std = @import("std");
const Instruction = @import("Instruction.zig");
const Allocator = std.mem.Allocator;

const Self = @This();

pub const Symbol = struct {
    name: ?[]const u8, // Currently unused
    addr: usize,
    size: usize,
};

code: []const Instruction,
entry: usize,
strings: []const []const u8,
field_names: []const []const u8,
num_globs: usize,
fn_tbl: ?std.ArrayList(Symbol) = null,
tokens: ?[]const []const u8 = null,
// This field is used if a program is constructed from
// Asm.zig or binary.zig.
deinit_data: ?struct {
    allocator: Allocator,
    strings: []const u8,
    field_names: []const u8,
    // TODO: move out of `deinit_data`, source is always contigous
    source: ?[]const u8,
} = null,

pub fn init(
    code: []const Instruction,
    entry: usize,
    strings: []const []const u8,
    field_names: []const []const u8,
    num_globs: usize,
) Self {
    return .{
        .code = code,
        .entry = entry,
        .strings = strings,
        .field_names = field_names,
        .num_globs = num_globs,
    };
}

pub fn deinit(self: *Self) void {
    if (self.deinit_data) |data| {
        data.allocator.free(self.strings);
        data.allocator.free(self.field_names);
        if (self.tokens) |tokens| data.allocator.free(tokens);
        data.allocator.free(self.code);
        data.allocator.free(data.strings);
        data.allocator.free(data.field_names);
        if (data.source) |source| data.allocator.free(source);
    }
    if (self.fn_tbl) |*fn_tbl| {
        fn_tbl.deinit();
    }
}
