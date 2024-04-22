//!
//! Represents the location of a substring within
//! a source file.
//!
const Self = @This();

/// The substring
string: []const u8,
/// The line number where the substring appears
line_num: usize,
/// The line where the substring appears as a substring
line: []const u8,
/// The offset of the substring within the line
offset: usize,

pub fn init(source: []const u8, substr: []const u8) !Self {
    var line_num: usize = 1;
    var location: usize = 0;
    var line_begin: usize = 0;
    const substr_loc: usize = @intFromPtr(substr.ptr) - @intFromPtr(source.ptr);
    if (substr_loc < 0 or substr_loc > source.len) return error.OutOfBounds;

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

pub fn print(self: Self, writer: anytype) !void {
    try writer.print("{s}\n", .{self.line});
    for (0..self.offset) |_| {
        try writer.writeByte(' ');
    }
    for (0..self.string.len) |_| {
        try writer.writeByte('~');
    }
    try writer.writeByte('\n');
}
