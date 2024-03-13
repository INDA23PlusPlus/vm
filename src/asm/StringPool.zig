//!
//! String pool
//! Stores deduplicated strings in a contiguous buffer
//!
const Self = @This();
const std = @import("std");

/// The start and end position of a string
/// in the contiguous buffer
pub const Entry = struct {
    begin: usize,
    end: usize,
};

/// Unique ID of a string in the pool
pub const ID = usize;

map: std.StringHashMap(ID),
entries: std.ArrayList(Entry),
contiguous: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .map = std.StringHashMap(ID).init(allocator),
        .entries = std.ArrayList(Entry).init(allocator),
        .contiguous = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
    self.entries.deinit();
    self.contiguous.deinit();
    self.* = undefined;
}

/// Add a string to the pool if not already present
/// Returns the unique identifier of the string
pub fn getOrIntern(self: *Self, string: []const u8) !ID {
    if (self.map.get(string)) |index| {
        return index;
    }
    const entry: Entry = .{
        .begin = self.contiguous.items.len,
        .end = self.contiguous.items.len + string.len,
    };
    // TODO: add null termination if we decide to use that for strings
    const slice = try self.contiguous.addManyAsSlice(string.len);
    const index = self.entries.items.len;
    std.mem.copy(u8, slice, string);
    try self.entries.append(entry);
    try self.map.put(string, index);
    return index;
}

/// Returns the entry corresponding to the given ID
/// The string can be obtained with pool.getContiguous()[entry.begin..entry.end]
pub fn resolve(self: *Self, index: ID) ?Entry {
    if (index >= self.entries.items.len) return null;
    return self.entries.items[index];
}

/// Returns the string corresponding to the given ID
/// WARNING: the string may be invalidated if the StringPool is mutated
/// after this call
pub fn resolveString(self: *Self, index: ID) ?[]const u8 {
    const entry = self.resolve(index) orelse return null;
    return self.contiguous.items[entry.begin..entry.end];
}

/// Returns the contiguous buffer
pub fn getContiguous(self: *Self) []const u8 {
    return self.contiguous.items;
}

test Self {
    const str_1 = "This is a string";
    const str_2 = "This is another string";

    var pool = Self.init(std.testing.allocator);
    defer pool.deinit();

    try std.testing.expect(try pool.getOrIntern(str_1) == 0);
    try std.testing.expect(try pool.getOrIntern(str_2) == 1);
    try std.testing.expect(try pool.getOrIntern(str_1) == 0);
    try std.testing.expect(try pool.getOrIntern(str_2) == 1);

    try std.testing.expect(pool.resolve(0) != null);
    try std.testing.expect(pool.resolve(1) != null);
    try std.testing.expect(pool.resolve(2) == null);

    const contiguous = pool.getContiguous();
    const res_0 = pool.resolve(0).?;
    const res_1 = pool.resolve(1).?;
    try std.testing.expect(std.mem.eql(u8, contiguous[res_0.begin..res_0.end], str_1));
    try std.testing.expect(std.mem.eql(u8, contiguous[res_1.begin..res_1.end], str_2));

    try std.testing.expect(std.mem.eql(u8, contiguous, "This is a stringThis is another string"));
}
