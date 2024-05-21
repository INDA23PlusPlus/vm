//!
//! Internal types for memory manager
//!

const APITypes = @import("APITypes.zig");
const std = @import("std");

pub const HeapType = struct {
    const CountType = @compileError("not using reference counting anymore");
    const MarkType = bool;
    const Self = @This();
    mark: MarkType,

    pub fn init() Self {
        return .{ .mark = false };
    }

    pub fn deinit(_: *const Self) void {}
};

pub const List = struct {
    const Self = @This();
    items: std.ArrayList(APITypes.Value),
    metadata: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .items = std.ArrayList(APITypes.Value).init(allocator),
            .metadata = HeapType.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        self.metadata.deinit();
    }
};

pub const Object = struct {
    const Self = @This();
    // TODO Maybe use AutoHashMapUnmanaged
    map: std.AutoHashMap(usize, APITypes.Value),
    metadata: HeapType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = std.AutoHashMap(usize, APITypes.Value).init(allocator),
            .metadata = HeapType.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.metadata.deinit();
    }
};
