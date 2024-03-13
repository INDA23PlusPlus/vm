const Self = @This();
const std = @import("std");
const int = @import("arch").int;

/// Holds the address of a symbol / label and a list of references to it
const Entry = struct {
    address: ?u64 = null,
    refs: std.ArrayList(*[8]u8),
    // TODO: Source reference

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .refs = std.ArrayList(*[8]u8).init(allocator),
        };
    }
};

/// Iterator over unresolved symbol names
const UnresolvedIterator = struct {
    iterator: std.StringArrayHashMap(Entry).Iterator,

    pub fn next(self: *UnresolvedIterator) ?[]const u8 {
        const entry = self.iterator.next() orelse return null;
        while (entry.?.value.address != null) {
            entry = self.iterator.next() orelse return null;
        }
        return entry.?.key;
    }
};

entries: std.StringArrayHashMap(Entry),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .entries = std.StringArrayHashMap(Entry).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.entries.deinit();
}

/// Either patches a reference or defers the patch until the referenced
/// symbol is resolved.
pub fn patch(self: *Self, name: []const u8, patch_location: *[8]u8) !void {
    var entry_result = try self.entries.getOrPut(name);

    // Create the entry if it does not exist
    if (!entry_result.found_existing) {
        entry_result.value_ptr.* = Entry.init(self.allocator);
    }

    var entry = entry_result.value_ptr.*;
    if (entry.address == null) {
        // The address of the referenced symbol has not been resolved yet
        // so we defer the patch
        try entry.refs.append(patch_location);
    } else {
        // Patch the reference
        int.encodeAddress(patch_location, entry.address.?);
    }
}

/// Resolves the address of a symbol so that previous and future patches
/// can be completed.
/// Returns an error if the symbol has already been resolved
pub fn resolve(self: *Self, name: []const u8, address: u64) !void {
    var entry_result = try self.entries.getOrPut(name);

    if (!entry_result.found_existing) {
        // Create the entry
        entry_result.value_ptr.* = Entry.init(self.allocator);
    } else {
        // Throw error if the symbol has already been resolved
        if (entry_result.value_ptr.address != null) {
            return error.AlreadyResolved;
        }
    }
    var entry = entry_result.value_ptr;
    entry.address = address;

    for (entry.refs.items) |patch_location| {
        int.encodeAddress(patch_location, address);
    }

    entry.refs.deinit();
}

/// Returns an iterator over the unresolved symbol names
pub fn unresolvedIterator(self: *Self) UnresolvedIterator {
    return .{ .iterator = self.entries.iterator() };
}

/// Resets the patcher
pub fn reset(self: *Self) void {
    self.entries.clearRetainingCapacity();
    self.unresolved = 0;
}
