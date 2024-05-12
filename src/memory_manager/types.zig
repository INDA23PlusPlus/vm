//!
//! Internal types for memory manager
//!

const APITypes = @import("APITypes.zig");
const std = @import("std");

pub const HeapType = struct {
    const CountType = u15;
    const MarkType = u1;
    const Self = @This();
    mark: bool,

    pub fn init() Self {
        return .{ .mark = false };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

pub const List = struct {
    const Self = @This();
    items: std.ArrayList(APITypes.Value),
    refs: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = std.ArrayList(APITypes.Value).init(allocator),
            .refs = HeapType.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.refs.deinit();
    }
};

pub const Object = struct {
    const Self = @This();
    // TODO Maybe use AutoHashMapUnmanaged
    map: std.AutoHashMap(usize, APITypes.Value),
    refs: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = std.AutoHashMap(usize, APITypes.Value).init(allocator),
            .refs = HeapType.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.refs.deinit();
    }
};
