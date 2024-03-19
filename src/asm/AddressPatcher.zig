//!
//! Used for patching references to labels / functions
//!
const Self = @This();
const std = @import("std");
const int = @import("arch").int;

/// Holds the address of a symbol / label and a list of references to it
const Entry = struct {
    address: ?usize = null,
    refs: std.ArrayList(usize),
    // TODO: Source reference

    pub fn init(allocator: std.mem.Allocator) Entry {
        return .{
            .refs = std.ArrayList(usize).init(allocator),
        };
    }
};

/// Iterator over unresolved symbol names
const UnresolvedIterator = struct {
    iterator: std.StringHashMap(Entry).Iterator,

    pub fn next(self: *UnresolvedIterator) ?[]const u8 {
        var entry = self.iterator.next() orelse return null;
        while (entry.value_ptr.address != null) {
            entry = self.iterator.next() orelse return null;
        }
        return entry.key_ptr.*;
    }
};

entries: std.StringHashMap(Entry),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .entries = std.StringHashMap(Entry).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.reset();
    self.entries.deinit();
}

/// Either patches a reference or defers the patch until the referenced
/// symbol is resolved.
pub fn patch(
    self: *Self,
    name: []const u8,
    patch_location: usize,
    code: []u8,
) !void {
    // Create the entry if it does not exist
    if (!self.entries.contains(name)) {
        try self.entries.put(name, Entry.init(self.allocator));
    }
    var entry = self.entries.getPtr(name).?;

    if (entry.address == null) {
        // The address of the referenced symbol has not been resolved yet
        // so we defer the patch
        try entry.refs.append(patch_location);
    } else {
        // Patch the reference
        int.encodeAddress(@ptrCast(code[patch_location .. patch_location + 8]), entry.address.?);
    }
}

/// Resolves the address of a symbol so that previous and future patches
/// can be completed.
/// Returns an error if the symbol has already been resolved
pub fn resolve(
    self: *Self,
    name: []const u8,
    address: usize,
    code: []u8,
) !void {
    // Create the entry if it does not exist
    if (!self.entries.contains(name)) {
        try self.entries.put(name, Entry.init(self.allocator));
    }
    var entry = self.entries.getPtr(name).?;

    // Check if the symbol has already been resolved
    if (entry.address != null) {
        return error.AlreadyResolved;
    }
    entry.address = address;

    // Patch previous references
    for (entry.refs.items) |patch_location| {
        int.encodeAddress(@ptrCast(code[patch_location .. patch_location + 8]), address);
    }

    entry.refs.clearRetainingCapacity();
}

/// Returns an iterator over the unresolved symbol names
pub fn unresolvedIterator(self: *Self) UnresolvedIterator {
    return .{ .iterator = self.entries.iterator() };
}

/// Resets the patcher
pub fn reset(self: *Self) void {
    var iterator = self.entries.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.refs.deinit();
    }
    self.entries.clearRetainingCapacity();
}
