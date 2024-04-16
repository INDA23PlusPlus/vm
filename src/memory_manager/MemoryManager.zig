const Self = @This();
const std = @import("std");
const APITypes = @import("APITypes.zig");
const ObjectRef = APITypes.ObjectRef;
const ListRef = APITypes.ListRef;
const types = @import("types.zig");
const RefCount = @import("RefCount.zig");
const Object = types.Object;
const List = types.List;

fn UnmanagedObjectList(comptime T: type) type {
    return std.ArrayListUnmanaged(*T);
}

allocator: std.mem.Allocator,
allObjects: UnmanagedObjectList(Object),
allLists: UnmanagedObjectList(List),

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .allObjects = try UnmanagedObjectList(Object).initCapacity(allocator, 0),
        .allLists = try UnmanagedObjectList(List).initCapacity(allocator, 0),
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
    self.allObjects.deinit(self.allocator);
    self.allLists.deinit(self.allocator);
}

pub fn alloc_struct(self: *Self) ObjectRef {
    var obj = self.allocator.create(Object) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };
    obj.* = Object.init(self.allocator);

    self.allObjects.append(self.allocator, obj) catch |e| {
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

    self.allLists.append(self.allocator, list) catch |e| {
        // TODO handle error, try gc then try again
        list.deinit_data();
        list.deinit_refcount();
        self.allocator.destroy(list);
        std.debug.panic("out of memory {}", .{e});
    };
    return ListRef{ .ref = list };
}

pub fn gc_pass(self: *Self) !void {
    //TODO implement gc method that detects and deallocates cycles

    try self.remove_unreachable_references(Object, &self.allObjects);
    try self.remove_unreachable_references(List, &self.allLists);
}

/// Remove all objects that have a refcount of 0, but do not deinit them.
/// Objects with a refcount of 0 are assumed to already have been deinitialized.
/// This function simply removes them from the internal array storing objects.
fn remove_unreachable_references(self: *Self, comptime T: type, list: *UnmanagedObjectList(T)) !void {
    // Init two pointers (read and write) to the start of the list
    // Iterate over the list, copying all objects that are still alive
    // to the write pointer, and incrementing the write pointer.
    // After the iteration, set the length of the list to the write pointer
    var read: usize = 0;
    var write: usize = 0;

    while (read < list.items.len) {
        const obj = list.items[read];
        if (obj.get_refcount() > 0) {
            list.items[write] = obj;
            write += 1;
        } else {
            // The data should already be deinitialized since the refcount == 0,
            // so we only need to deinit the refcount
            obj.deinit_refcount();
            self.allocator.destroy(obj);
        }
        read += 1;
    }

    // The write pointer now describes how many objects were kept.
    // Shrink the list to this amount to free the memory.
    list.shrinkAndFree(self.allocator, write);
}

/// Get the amount of objects that the memory manager stores.
/// This includes objects that have a refcount of 0 (garbage) and that will be
/// removed the next gc pass.
pub fn get_object_count(self: *Self) usize {
    return self.allObjects.items.len + self.allLists.items.len;
}

// TODO: create test for this

test "get and set to struct" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef = memoryManager.alloc_struct();

    try objectRef.set(123, Type{ .int = 456 });

    try std.testing.expect(456 == objectRef.get(123).?.int);
}

test "get and set to list" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var listRef = memoryManager.alloc_list();

    try listRef.push(Type{ .int = 123 });

    try std.testing.expect(1 == listRef.length());
    try std.testing.expect(123 == listRef.get(0).?.int);
}

test "run gc pass with empty memory manager" {
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    try memoryManager.gc_pass();
}

test "gc pass removes one unused object" {
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef = memoryManager.alloc_struct();

    try std.testing.expect(1 == memoryManager.get_object_count());

    objectRef.decr();
    try memoryManager.gc_pass();

    try std.testing.expect(0 == memoryManager.get_object_count());
}

test "gc pass keeps one object still in use" {
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    _ = memoryManager.alloc_struct();

    try std.testing.expect(1 == memoryManager.get_object_count());

    try memoryManager.gc_pass();

    try std.testing.expect(1 == memoryManager.get_object_count());
}

test "gc pass keeps one object still in use and discards one unused" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    var objectRef2 = memoryManager.alloc_struct();

    try objectRef1.set(123, Type{ .int = 456 });

    try std.testing.expect(2 == memoryManager.get_object_count());

    objectRef2.decr();
    try memoryManager.gc_pass();

    try std.testing.expect(1 == memoryManager.get_object_count());
    try std.testing.expect(456 == objectRef1.get(123).?.int);
}
