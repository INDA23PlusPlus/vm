//!
//! Exposed types from memory manager for use in VM
//!
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;

pub const ListRef = struct {
    const Self = @This();
    ref: *List,

    pub fn incr(self: *Self) void {
        self.ref.refcount.increment();
    }

    pub fn decr(self: *Self) void {
        self.ref.refcount.decrement();
    }
};

pub const ObjectRef = struct {
    const Self = @This();
    ref: *Object,

    pub fn incr(self: *Self) void {
        self.ref.refcount.increment();
    }

    pub fn decr(self: *Self) void {
        self.ref.refcount.decrement();
    }
};
