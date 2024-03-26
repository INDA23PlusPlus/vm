const Self = @This();
const std = @import("std");
const APITypes = @import("APITypes.zig");
const ObjectRef = APITypes.ObjectRef;
const ListRef = APITypes.ListRef;
const types = @import("types.zig");
const RefCount = @import("RefCount.zig");
const Object = types.Object;
const List = types.List;

// TODO idk if storing the allocator is best, or if we should pass one to all
//      function calls. Storing has the advantage that we can garantee to call
//      destroy on the same allocator as objects and lists were created from.
allocator: std.mem.Allocator,
allObjects: std.ArrayList(*Object),
allLists: std.ArrayList(*List),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .allObjects = std.ArrayList(*Object).init(allocator),
        .allLists = std.ArrayList(*List).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.allObjects.items) |value| {
        value.deinit();
        self.allocator.destroy(value);
    }
    for (self.allLists.items) |value| {
        value.deinit();
        self.allocator.destroy(value);
    }
    self.allObjects.deinit();
    self.allLists.deinit();
}

pub fn alloc_struct(self: *Self, allocator: std.mem.Allocator) ObjectRef {
    var obj = allocator.create(Object) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };
    obj.* = Object.init(allocator);

    self.allObjects.append(obj) catch |e| {
        // TODO handle error, try gc then try again
        obj.deinit();
        allocator.destroy(obj);
        std.debug.panic("out of memory {}", .{e});
    };

    return ObjectRef{ .ref = obj };
}

pub fn alloc_list(self: *Self, allocator: std.mem.Allocator) ListRef {
    var list = allocator.create(List) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    list.* = List.init(allocator);

    self.allLists.append(list) catch |e| {
        // TODO handle error, try gc then try again
        list.deinit();
        allocator.destroy(list);
        std.debug.panic("out of memory {}", .{e});
    };
    return ListRef{ .ref = list };
}

// TODO: create test for this

test "get and set to struct" {
    const Type = types.Type;
    var memoryManager = Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef = memoryManager.alloc_struct(std.testing.allocator);

    try objectRef.set(123, Type{ .int = 456 });

    try std.testing.expect(456 == objectRef.get(123).?.int);
}

test "get and set to list" {
    const Type = types.Type;
    var memoryManager = Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var listRef = memoryManager.alloc_list(std.testing.allocator);

    try listRef.push(Type{ .int = 123 });

    try std.testing.expect(1 == listRef.length());
    try std.testing.expect(123 == listRef.get(0).?.int);
}
