//!
//! Internal types for memory manager
//!

const RefCount = @import("RefCount.zig");
const APITypes = @import("APITypes.zig");
const std = @import("std");

pub const HeapType = struct {
    const Self = @This();
    refcount: RefCount, // all reference count

    pub fn init() Self {
        return .{ .refcount = RefCount.init() };
    }

    pub fn deinit_refcount(self: *Self) void {
        self.refcount.deinit();
    }

    pub fn deinit_refcount_unchecked(self: *Self) void {
        self.refcount.deinit_unchecked();
    }

    pub fn get_refcount(self: *Self) u32 {
        return self.refcount.get();
    }

    pub fn incr(self: *Self) void {
        _ = self.refcount.increment();
    }

    pub fn decr(self: *Self) u32 {
        return self.refcount.decrement();
    }
};

pub const List = struct {
    const Self = @This();
    // TODO Maybe use ArrayList
    items: std.ArrayList(APITypes.Type),
    refs: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = std.ArrayList(APITypes.Type).init(allocator),
            .refs = HeapType.init(),
        };
    }

    pub fn deinit_data(self: *Self) void {
        for (self.items.items) |*item| {
            switch (item.*) {
                .list => item.list.decr(),
                .object => item.object.decr(),
                else => {},
            }
        }
        self.items.deinit();
    }

    pub fn incr(self: *Self) void {
        _ = self.refs.incr();
    }

    pub fn decr(self: *Self) void {
        const old_count = self.refs.decr();

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
    refs: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = std.AutoHashMap(usize, APITypes.Type).init(allocator),
            .refs = HeapType.init(),
        };
    }

    pub fn deinit_data(self: *Self) void {
        var it = self.map.valueIterator();
        while (it.next()) |val| {
            switch (val.*) {
                .list => val.list.decr(),
                .object => val.object.decr(),
                else => {},
            }
        }
        self.map.deinit();
    }

    pub fn incr(self: *Self) void {
        _ = self.refs.incr();
    }

    pub fn decr(self: *Self) void {
        const old_count = self.refs.decr();

        // If this was the last reference, deinit the data
        if (old_count == 1) {
            self.deinit_data();
        }
    }
};
