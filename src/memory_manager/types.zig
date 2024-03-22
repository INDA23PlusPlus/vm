//!
//! Internal types for memory manager
//!

const RefCount = @import("RefCount.zig");
const std = @import("std");

pub const List = struct {
    const Self = @This();
    items: std.ArrayList(Types),

    refcount: RefCount = RefCount.init(), // stack references

    pub fn init(allocator: std.heap.Allocator) Self {
        return .{ .items = std.ArrayList(Types).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.refcount.deinit();
    }
};

pub const Object = struct {
    const Self = @This();
    // TODO: add an actual internal representation, some kind of hashmap
    map: std.AutoHashMap(u32, Types), // TODO figure out type of key

    refcount: RefCount = RefCount.init(), // stack references

    pub fn init(allocator: std.heap.Allocator) Self {
        return .{ .map = std.AutoHashMap(u32, Types).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.refcount.deinit();
    }
};

pub const Types = union {
    unit: @TypeOf(.{}),
    int: i64,
    float: f64,
    list: List,
    object: Object,
};
