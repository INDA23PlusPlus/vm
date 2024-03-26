//!
//! Internal types for memory manager
//!

const RefCount = @import("RefCount.zig");
const std = @import("std");

pub const List = struct {
    const Self = @This();
    // TODO Maybe use ArrayList
    items: std.ArrayList(Type),

    refcount: RefCount = RefCount.init(), // stack references

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .items = std.ArrayList(Type).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.refcount.deinit();
    }
};

pub const Object = struct {
    const Self = @This();
    // TODO Maybe use AutoHashMapUnmanaged
    map: std.AutoHashMap(u32, Type),

    refcount: RefCount = RefCount.init(), // stack references

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .map = std.AutoHashMap(u32, Type).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.refcount.deinit();
    }
};

pub const Type = union(enum) {
    unit: @TypeOf(.{}),
    int: i64,
    float: f64,
    list: List,
    object: Object,
};
