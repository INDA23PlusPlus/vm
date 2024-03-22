const Self = @This();
const std = @import("std");
const APITypes = @import("APITypes.zig");
const ObjectRef = APITypes.ObjectRef;
const ListRef = APITypes.ListRef;
const types = @import("types.zig");
const RefCount = @import("RefCount.zig");
const Object = types.Object;
const List = types.List;

allObjects: std.ArrayList(Object),
allLists: std.ArrayList(List),

pub fn alloc_struct(self: *Self, allocator: std.mem.Allocator) ObjectRef {
    // TODO

    const obj = Object.init(allocator);
    self.allObjects.append(obj) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    const ref = ObjectRef{ .ref = &obj };

    return ref;
}

pub fn alloc_list(self: *Self, allocator: std.mem.Allocator) ListRef {
    const list = List.init(allocator);
    self.allLists.append(list) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    const ref = ObjectRef{ .ref = &list };

    return ref;
}
