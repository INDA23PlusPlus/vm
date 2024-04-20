//!
//! Parses strings and replaces escape characters.
//!

const std = @import("std");
const Error = @import("Error.zig");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const StringParser = @This();

buffer: ArrayList(u8),
errors: *ArrayList(Error),

const CharIterator = struct {
    string: []const u8,
    index: usize = 0,

    pub fn next(self: *CharIterator) ?u8 {
        if (self.index < self.string.len) {
            defer self.index += 1;
            return self.string[self.index];
        } else return null;
    }
};

pub fn init(allocator: Allocator, errors: *ArrayList(Error)) StringParser {
    return .{
        .buffer = ArrayList(u8).init(allocator),
        .errors = errors,
    };
}

pub fn deinit(self: *StringParser) void {
    self.buffer.deinit();
}

/// String returned is temporary, and is invalidated when `parse` is called again.
pub fn parse(self: *StringParser, string: []const u8) ![]const u8 {
    self.buffer.clearRetainingCapacity();
    const writer = self.buffer.writer();
    var iter = CharIterator{ .string = string };

    while (iter.next()) |c| {
        switch (c) {
            '\\' => {
                if (iter.next()) |e| {
                    switch (e) {
                        'n' => try writer.writeByte('\n'),
                        '\\' => try writer.writeByte('\\'),
                        '\"' => try writer.writeByte('\"'),
                        // TODO: more escape characters
                        else => try self.errors.append(.{
                            .tag = .@"Invalid escape character",
                            .where = string[iter.index - 1 .. iter.index],
                        }),
                    }
                } else {
                    try self.errors.append(.{
                        .tag = .@"Missing escape character",
                        .where = string[iter.index - 1 .. iter.index],
                    });
                }
            },
            else => try writer.writeByte(c),
        }
    }

    return self.buffer.items;
}
