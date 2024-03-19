//!
//! Exposed types from memory manager for use in VM
//!

pub const ListRef = struct {
    const Self = @This();
    pub fn incr(_: *Self) void {}
    pub fn decr(_: *Self) void {}
};

pub const ObjectRef = struct {
    const Self = @This();
    pub fn incr(_: *Self) void {}
    pub fn decr(_: *Self) void {}
};
