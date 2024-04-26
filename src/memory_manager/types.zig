//!
//! Internal types for memory manager
//!

const metadata = @import("metadata.zig");
const APITypes = @import("APITypes.zig");
const std = @import("std");

pub const HeapType = struct {
    const CountType = u15;
    const MarkType = u1;
    const Metadata = metadata.Metadata(CountType, MarkType);
    const Self = @This();
    metadata: Metadata, // reference count from stack only

    pub fn init() Self {
        return .{ .metadata = Metadata.init() };
    }

    pub fn deinit(self: *Self) void {
        self.metadata.deinit();
    }

    pub fn deinit_unchecked(self: *Self) void {
        self.metadata.deinit_unchecked();
    }

    pub fn get_stack_refcount(self: *Self) u32 {
        return self.metadata.get();
    }

    pub fn incr(self: *Self) void {
        self.metadata.increment();
    }

    pub fn decr(self: *Self) void {
        self.metadata.decrement();
    }
};

comptime {
    if (@bitSizeOf(HeapType) != @bitSizeOf(HeapType.CountType) + @bitSizeOf(HeapType.MarkType)) {
        @compileError("fixme");
    }
}

pub const List = struct {
    const Self = @This();
    items: std.ArrayList(APITypes.Type),
    refs: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = std.ArrayList(APITypes.Type).init(allocator),
            .refs = HeapType.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.refs.deinit();
    }

    pub fn incr(self: *Self) void {
        self.refs.incr();
    }

    pub fn decr(self: *Self) void {
        self.refs.decr();
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

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.refs.deinit();
    }

    pub fn incr(self: *Self) void {
        self.refs.incr();
    }

    pub fn decr(self: *Self) void {
        self.refs.decr();
    }
};
