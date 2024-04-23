//!
//! Internal types for memory manager
//!

const RefCount = @import("RefCount.zig");
const APITypes = @import("APITypes.zig");
const std = @import("std");

pub const List = struct {
    const Self = @This();
    // TODO Maybe use ArrayList
    items: std.ArrayList(APITypes.Type),

    refcount: RefCount = RefCount.init(), // all reference count

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .items = std.ArrayList(APITypes.Type).init(allocator) };
    }

    pub fn deinit_data(self: *Self) void {
        for (self.items.items) |*item| {
            switch (item.*) {
                APITypes.Type.list => item.list.decr(),
                APITypes.Type.object => item.object.decr(),
                else => {},
            }
        }
        self.items.deinit();
    }

    pub fn get_refcount(self: *Self) u32 {
        return self.refcount.get();
    }

    pub fn deinit_refcount(self: *Self) void {
        self.refcount.deinit();
    }

    pub fn deinit_refcount_unchecked(self: *Self) void {
        self.refcount.deinit_unchecked();
    }

    pub fn incr(self: *Self) void {
        _ = self.refcount.increment();
    }

    pub fn decr(self: *Self) void {
        var old_count = self.refcount.decrement();

        // If this was the last reference, deinit the data
        if (old_count == 1) {
            self.deinit_data();
        }
    }
};

pub const Object = struct {
    const Self = @This();
    // TODO Maybe use AutoHashMapUnmanaged
    map: std.AutoHashMap(usize, APITypes.Type),

    refcount: RefCount = RefCount.init(), // all reference count

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .map = std.AutoHashMap(usize, APITypes.Type).init(allocator) };
    }

    pub fn deinit_data(self: *Self) void {
        var it = self.map.valueIterator();
        while (it.next()) |val| {
            switch (val.*) {
                APITypes.Type.list => val.list.decr(),
                APITypes.Type.object => val.object.decr(),
                else => {},
            }
        }
        self.map.deinit();
    }

    pub fn get_refcount(self: *Self) u32 {
        return self.refcount.get();
    }

    pub fn deinit_refcount(self: *Self) void {
        self.refcount.deinit();
    }

    pub fn deinit_refcount_unchecked(self: *Self) void {
        self.refcount.deinit_unchecked();
    }

    pub fn incr(self: *Self) void {
        _ = self.refcount.increment();
    }

    pub fn decr(self: *Self) void {
        var old_count = self.refcount.decrement();

        // If this was the last reference, deinit the data
        if (old_count == 1) {
            self.deinit_data();
        }
    }
};
