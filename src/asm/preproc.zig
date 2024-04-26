//!
//! Assembly source preprocessing.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn run(source: []const u8, allocator: Allocator) ![]const u8 {
    var buffer = ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    for (source) |char| {
        switch (char) {
            '\t' => try buffer.writer().writeAll("    "),
            else => try buffer.append(char),
        }
    }

    buffer.shrinkAndFree(buffer.items.len);

    return buffer.items;
}

test {
    const testing = std.testing;
    const source = "Hello\tthere";
    const preprocessed = try run(source, testing.allocator);
    defer testing.allocator.free(preprocessed);
    try testing.expectEqualSlices(u8, "Hello    there", preprocessed);
}
