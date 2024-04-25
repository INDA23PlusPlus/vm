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
                APITypes.Type.list => item.list.deinit(),
                APITypes.Type.object => item.object.deinit(),
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
            self.deinit();
        }
    }

    // Deinitialize the object, this is called when the reference count reaches 0
    fn deinit(self: *Self) void {
        self.deinit_data();
        self.refs.deinit_refcount();
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
                APITypes.Type.list => val.list.deinit(),
                APITypes.Type.object => val.object.deinit(),
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
            self.deinit();
        }
    }

    // Deinitialize the object, this is called when the reference count reaches 0
    fn deinit(self: *Self) void {
        self.deinit_data();
        self.refs.deinit_refcount();
    }
};
