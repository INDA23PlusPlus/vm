//!
//! Represents the location of a substring within
//! a source file.
//!
const Self = @This();
const std = @import("std");

pub const terminal_colors = struct {
    pub const reset = "\x1b[0m";
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
};

/// The substring
string: []const u8,
/// The line number where the substring appears
line_num: usize,
/// The line where the substring appears as a substring
line: []const u8,
/// The offset of the substring within the line.
/// The actual line may have to be scanned for tabs
/// in order to print diagnostics correctly.
offset: usize,

pub fn init(source: []const u8, substr: []const u8) !Self {
    var line_num: usize = 1;
    var location: usize = 0;
    var line_begin: usize = 0;
    const substr_loc = std.math.sub(usize, @intFromPtr(substr.ptr), @intFromPtr(source.ptr)) catch return error.SourceRefOutOfBounds;

    if (substr_loc > source.len) return error.SourceRefOutOfBounds;

    while (location < substr_loc) {
        if (source[location] == '\n') {
            line_num += 1;
            location += 1;
            line_begin = location;
            continue;
        }
        location += 1;
    }

    const offset = location - line_begin;

    while (location < source.len and source[location] != '\n') {
        location += 1;
    }

    const line = source[line_begin..location];

    return .{
        .string = substr,
        .line_num = line_num,
        .line = line,
        .offset = offset,
    };
}

pub fn print(self: Self, writer: anytype, color: ?[]const u8) !void {
    try writer.print("{s}\n", .{self.line});
    for (0..self.offset) |i| {
        const c: u8 = if (self.line[i] == '\t') '\t' else ' ';
        try writer.writeByte(c);
    }

    if (color) |c| try writer.writeAll(c);
    for (0..self.string.len) |_| {
        try writer.writeByte('~');
    }
    if (color) |_| try writer.writeAll(terminal_colors.reset);

    try writer.writeByte('\n');
}
