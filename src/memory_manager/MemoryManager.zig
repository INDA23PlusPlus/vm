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
        if (value.refs.get_refcount() > 0) {
            // Deinit map directly, because all children will
            // eventually be deinit'ed by this loop.
            value.map.deinit();
        }
        value.refs.deinit_refcount_unchecked();
        self.allocator.destroy(value);
    }
    for (self.allLists.items) |value| {
        if (value.refs.get_refcount() > 0) {
            // Deinit list directly, because all children will
            // eventually be deinit'ed by this loop.
            value.items.deinit();
        }
        value.refs.deinit_refcount_unchecked();
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

const Direction = enum(i8) {
    decrement = -1,
    increment = 1,
};

fn should_recurse(comptime T: type, val: *T, root: *void, direction: Direction) bool {
    if (root == val) {
        return false;
    }
    switch (val.ref.refcount) {
        0 => return direction == Direction.decrement,
        1 => return direction == Direction.increment,
        else => return false,
    }
}

fn tracing_cycle_detection_object(obj: *Object, root: *void, direction: Direction) void {
    var it = obj.map.valueIterator();

    while (it.next()) |val| {
        switch (val.*) {
            ObjectRef => {
                val.ref.refcount += direction;

                if (should_recurse(Object, val.ref, root, direction)) {
                    tracing_cycle_detection_object(val.ref, root, direction);
                }
            },
            ListRef => {
                val.refs.refcount += direction;

                if (should_recurse(List, val.ref, root, direction)) {
                    tracing_cycle_detection_list(val.ref, root, direction);
                }
            },
            else => {},
        }
    }
}

fn tracing_cycle_detection_list(list: *List, root: *void, direction: Direction) void {
    for (list.items.items) |*val| {
        switch (val.*) {
            Object => {
                val.refcount += direction;

                if (should_recurse(Object, val, root, direction)) {
                    tracing_cycle_detection_object(val, root, direction);
                }
            },
            List => {
                val.refcount += direction;

                if (should_recurse(List, val, root, direction)) {
                    tracing_cycle_detection_list(val, root, direction);
                }
            },
            else => {},
        }
    }
}

/// Detect cycles in the object graph and remove them.
/// TODO: Mark visited objects to reduce time complexity from O(n^2) to O(n)
fn cycle_detection(comptime T: type, cycle_candidates: *UnmanagedObjectList(T)) !void {
    for (cycle_candidates.items) |value| {
        const refcount = value.refs.get_refcount();
        if (refcount > 0) {
            switch (T) {
                Object => {
                    tracing_cycle_detection_object(value, value, Direction.decrement);
                },
                List => {
                    tracing_cycle_detection_list(value, value, Direction.decrement);
                },
                else => unreachable,
            }

            // If the refcount is 0, then the object was only referenced by itself
            // and should be removed, otherwise restore the refcount
            if (value.ref.refcount == 0) {
                value.deinit();
            } else {
                switch (T) {
                    Object => {
                        tracing_cycle_detection_object(value, value, Direction.increment);
                    },
                    List => {
                        tracing_cycle_detection_list(value, value, Direction.increment);
                    },
                    else => unreachable,
                }
            }
        }
    }

    cycle_candidates.shrinkAndFree(Self.allocator, 0);
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
        if (obj.refs.get_refcount() > 0) {
            list.items[write] = obj;
            write += 1;
        } else {
            // The data should already be deinitialized since the refcount == 0,
            // so we only need to deinit the refcount
            obj.refs.deinit_refcount();
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
