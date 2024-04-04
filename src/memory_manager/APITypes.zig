//!
//! Exposed types from memory manager for use in VM
//!
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;
const Type = types.Type;

pub const ListRef = struct {
    const Self = @This();
    ref: *List,

    pub fn incr(self: *const Self) void {
        _ = self.ref.refcount.increment();
    }

    pub fn decr(self: *const Self) void {
        _ = self.ref.refcount.decrement();
    }

    pub fn length(self: *Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *Self, index: usize) ?Type {
        return self.ref.items.items[index];
    }

    pub fn set(self: *Self, key: usize, value: Type) void {
        self.ref.items.items[key] = value;
    }

    pub fn push(self: *Self, value: Type) !void {
        try self.ref.items.append(value);
    }
};

pub const ObjectRef = struct {
    const Self = @This();
    ref: *Object,

    pub fn incr(self: *const Self) void {
        _ = self.ref.incr();
    }

    pub fn decr(self: *const Self) void {
        _ = self.ref.decr();
    }

    pub fn get(self: *Self, key: u32) ?Type {
        return self.ref.map.get(key);
    }

    pub fn set(self: *Self, key: u32, value: Type) !void {
        try self.ref.map.put(key, value);
    }
};
