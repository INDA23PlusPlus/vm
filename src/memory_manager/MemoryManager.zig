const Self = @This();
const std = @import("std");
const APITypes = @import("APITypes.zig");
const ObjectRef = APITypes.ObjectRef;
const ListRef = APITypes.ListRef;
const types = @import("types.zig");
const metadata = @import("metadata.zig");
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
        value.refs.metadata.count = 0;
        value.deinit();
        self.allocator.destroy(value);
    }
    for (self.allLists.items) |value| {
        value.refs.metadata.count = 0;
        value.deinit();
        self.allocator.destroy(value);
    }
    self.allObjects.deinit(self.allocator);
    self.allLists.deinit(self.allocator);
}

pub fn alloc_struct(self: *Self) ObjectRef {
    var objRef = ObjectRef.init(self.allocator) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    self.allObjects.append(self.allocator, objRef.ref) catch |e| {
        // TODO handle error, try gc then try again
        objRef.deinit();
        std.debug.panic("out of memory {}", .{e});
    };

    return objRef;
}

pub fn alloc_list(self: *Self) ListRef {
    var listRef = ListRef.init(self.allocator) catch |e| {
        // TODO handle error, try gc then try again
        std.debug.panic("out of memory {}", .{e});
    };

    self.allLists.append(self.allocator, listRef.ref) catch |e| {
        // TODO handle error, try gc then try again
        listRef.deinit();
        std.debug.panic("out of memory {}", .{e});
    };
    return listRef;
}

pub fn gc_pass(self: *Self) !void {
    //TODO implement gc method that detects and deallocates cycles

    try self.remove_unreachable_references(Object, &self.allObjects);
    try self.remove_unreachable_references(List, &self.allLists);
}

fn mark_item(item: *APITypes.Type) void {
    switch (item.*) {
        .object => |*inner| {
            if (inner.ref.refs.metadata.mark == 0) {
                inner.ref.refs.metadata.mark = 1;
                mark(Object, inner.ref);
            }
        },
        .list => |*inner| {
            if (inner.ref.refs.metadata.mark == 0) {
                inner.ref.refs.metadata.mark = 1;
                mark(List, inner.ref);
            }
        },
        else => {},
    }
}

fn mark(comptime T: type, obj: *T) void {
    switch (T) {
        List => {
            for (obj.*.items.items) |*item| {
                mark_item(item);
            }
        },
        Object => {
            var it = obj.map.valueIterator();
            while (it.next()) |item| {
                mark_item(item);
            }
        },
        else => |t| @compileError("Cannot mark " ++ @typeName(t)),
    }
}

/// Remove all objects that have a refcount of 0, but do not deinit them.
/// Objects with a refcount of 0 are assumed to already have been deinitialized.
/// This function simply removes them from the internal array storing objects.
fn remove_unreachable_references(self: *Self, comptime T: type, list: *UnmanagedObjectList(T)) !void {
    // Mark roots (objects on the stack)
    for (list.items) |obj| {
        obj.refs.metadata.mark = @intFromBool(obj.refs.get_stack_refcount() > 0);
        if (obj.refs.metadata.mark > 0) {
            mark(T, obj);
        }
    }

    // Sweep
    // Actually drop and remove garbage objects.
    //
    // Init two pointers (read and write) to the start of the list
    // Iterate over the list, copying all objects that are still alive
    // to the write pointer, and incrementing the write pointer.
    // After the iteration, set the length of the list to the write pointer
    var read: usize = 0;
    var write: usize = 0;

    while (read < list.items.len) {
        const obj = list.items[read];
        if (obj.refs.metadata.mark > 0) {
            // Keep this object
            list.items[write] = obj;
            write += 1;
        } else {
            // Drop this garbage since it was not marked
            obj.deinit();
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
    try std.testing.expect(123 == listRef.get(0).int);
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

    objectRef.deinit();
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

    objectRef2.deinit();
    try memoryManager.gc_pass();

    try std.testing.expect(1 == memoryManager.get_object_count());
    try std.testing.expect(456 == objectRef1.get(123).?.int);
}

test "assign object to object" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    var objectRef2 = memoryManager.alloc_struct();
    try objectRef1.set(123, Type{ .int = 456 });
    try objectRef2.set(123, Type{ .object = objectRef1 });
    try std.testing.expect(2 == memoryManager.get_object_count());
}

test "object in object, drop parent, keep child" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type{ .int = 456 }); // A[123] = 456
    try objectB.set(123, Type{ .object = objectA }); // B[123] = A
    try std.testing.expect(2 == memoryManager.get_object_count());

    // Drop object B from stack. The child A should still be kept since it
    // is referenced on the stack.
    objectB.decr();
    // Object B should be dropped
    try memoryManager.gc_pass();
    // Only Object A should be alive.
    try std.testing.expect(1 == memoryManager.get_object_count());

    try std.testing.expect(456 == objectA.get(123).?.int);
}

test "object in object, drop child from stack, gc, both stay" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type{ .int = 456 }); // A[123] = 456
    try objectB.set(123, Type{ .object = objectA }); // B[123] = A
    try std.testing.expect(2 == memoryManager.get_object_count());

    // Drop object A from stack. It should still be kept since it is alive as a child of object B.
    objectA.decr();
    try memoryManager.gc_pass();
    try std.testing.expect(2 == memoryManager.get_object_count());
}

test "cycles get dropped" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(124, Type{ .object = objectA }); // A[124] = B
    try objectB.set(123, Type{ .object = objectA }); // B[123] = A
    try std.testing.expect(2 == memoryManager.get_object_count());

    // Drop both from stack.
    // They should both
    objectA.decr();
    objectB.decr();
    try memoryManager.gc_pass();
    try std.testing.expect(0 == memoryManager.get_object_count());
}
