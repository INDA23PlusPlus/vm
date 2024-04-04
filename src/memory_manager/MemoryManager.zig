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
        value.deinit_data();
        value.deinit_refcount_unchecked();
        self.allocator.destroy(value);
    }
    for (self.allLists.items) |value| {
        value.deinit_data();
        value.deinit_refcount_unchecked();
        self.allocator.destroy(value);
    }
    self.allObjects.deinit();
    self.allLists.deinit();
}

pub fn alloc_struct(self: *Self) ObjectRef {
    var obj = self.allocator.create(Object) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };
    obj.* = Object.init(self.allocator);

    self.allObjects.append(obj) catch |e| {
        // TODO handle error, try gc then try again
        obj.deinit_data();
        obj.deinit_refcount();
        self.allocator.destroy(obj);
        std.debug.panic("out of memory {}", .{e});
    };

    return ObjectRef{ .ref = obj };
}

pub fn alloc_list(self: *Self) ListRef {
    var list = self.allocator.create(List) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    list.* = List.init(self.allocator);

    self.allLists.append(list) catch |e| {
        // TODO handle error, try gc then try again
        list.deinit_data();
        list.deinit_refcount();
        self.allocator.destroy(list);
        std.debug.panic("out of memory {}", .{e});
    };
    return ListRef{ .ref = list };
}

pub fn gc_pass(self: *Self) !void {
    self.remove_unreachable_references();
}

/// Remove all objects that have a refcount of 0, but do not deinit them.
/// Objects with a refcount of 0 are assumed to already have been deinitialized.
/// This function simply removes them from the internal array storing objects.
fn remove_unreachable_references(self: *Self) void {
    // Init two pointers (read and write) to the start of the list
    // Iterate over the list, copying all objects that are still alive
    // to the write pointer, and incrementing the write pointer.
    // After the iteration, set the length of the list to the write pointer
    var read = 0;
    var write = 0;

    while (read < self.allObjects.items.len) {
        const obj = self.allObjects.items[read];
        if (RefCount.get(obj) > 0) {
            self.allObjects.items[write] = obj;
            write += 1;
        } else {
            // The data should already be deinitialized since the refcount == 0,
            // so we only need to deinit the refcount
            obj.deinit_refcount();
            self.allocator.destroy(obj);
        }
        read += 1;
    }
}

// TODO: create test for this

test "get and set to struct" {
    const Type = types.Type;
    var memoryManager = Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef = memoryManager.alloc_struct();

    try objectRef.set(123, Type{ .int = 456 });

    try std.testing.expect(456 == objectRef.get(123).?.int);
}

test "get and set to list" {
    const Type = types.Type;
    var memoryManager = Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var listRef = memoryManager.alloc_list();

    try listRef.push(Type{ .int = 123 });

    try std.testing.expect(1 == listRef.length());
    try std.testing.expect(123 == listRef.get(0).?.int);
}
