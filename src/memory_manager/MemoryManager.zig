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

    try objectRef.set(123, Type.from(456));

    try std.testing.expectEqual(456, objectRef.get(123).?.int);
}

test "get and set to list" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var listRef = memoryManager.alloc_list();

    try listRef.push(Type.from(123));

    try std.testing.expectEqual(1, listRef.length());
    try std.testing.expectEqual(123, listRef.get(0).int);
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

    try std.testing.expectEqual(1, memoryManager.get_object_count());

    objectRef.deinit();
    try memoryManager.gc_pass();

    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "gc pass keeps one object still in use" {
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    _ = memoryManager.alloc_struct();

    try std.testing.expectEqual(1, memoryManager.get_object_count());

    try memoryManager.gc_pass();

    try std.testing.expectEqual(1, memoryManager.get_object_count());
}

test "gc pass keeps one object still in use and discards one unused" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    var objectRef2 = memoryManager.alloc_struct();

    try objectRef1.set(123, Type.from(456));

    try std.testing.expectEqual(2, memoryManager.get_object_count());

    objectRef2.deinit();
    try memoryManager.gc_pass();

    try std.testing.expectEqual(1, memoryManager.get_object_count());
    try std.testing.expectEqual(456, objectRef1.get(123).?.int);
}

test "assign object to object" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    var objectRef2 = memoryManager.alloc_struct();
    try objectRef1.set(123, Type.from(456));
    try objectRef2.set(123, Type.from(objectRef1));
    try std.testing.expectEqual(2, memoryManager.get_object_count());
}

test "object in object, drop parent, keep child" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type.from(456)); // A[123] = 456
    try objectB.set(123, Type.from(objectA)); // B[123] = A
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop object B from stack. The child A should still be kept since it
    // is referenced on the stack.
    objectB.decr();
    // Object B should be dropped
    try memoryManager.gc_pass();
    // Only Object A should be alive.
    try std.testing.expectEqual(1, memoryManager.get_object_count());

    try std.testing.expectEqual(456, objectA.get(123).?.int);
}

test "object in object, drop child from stack, gc, both stay" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type.from(456)); // A[123] = 456
    try objectB.set(123, Type.from(objectA)); // B[123] = A
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop object A from stack. It should still be kept since it is alive as a child of object B.
    objectA.decr();
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());
}

test "cycles get dropped" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(124, Type.from(objectA)); // A[124] = B
    try objectB.set(123, Type.from(objectA)); // B[123] = A
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop both from stack.
    // They should both
    objectA.decr();
    objectB.decr();
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "one object refers to same object twice" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    try objectA.set(1, Type.from(objectB)); // A[1] = B
    objectB.decr(); // all references to B are from A

    try std.testing.expectEqual(2, memoryManager.get_object_count());

    objectA.decr();
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "object key set twice with same value" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    objectB.decr(); // all references to B are from A

    try std.testing.expectEqual(2, memoryManager.get_object_count());

    objectA.decr(); // drop A
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "big cycle" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    var objects = std.ArrayList(ObjectRef).init(std.testing.allocator);
    defer objects.deinit();

    const cycle_len = 128;

    for (0..cycle_len) |_| {
        try objects.append(memoryManager.alloc_struct());
    }

    for (0..cycle_len) |i| {
        try objects.items[(i + 1) % cycle_len].set(0, Type.from(objects.items[i]));
    }

    try std.testing.expectEqual(cycle_len, memoryManager.get_object_count());

    for (0..cycle_len) |i| {
        objects.items[i].decr();
    }

    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "tree of objects with references to root" {
    const Type = APITypes.Type;
    var memoryManager = try Self.init(std.testing.allocator);
    defer memoryManager.deinit();

    const utils = struct {
        fn buildTree(cur: ObjectRef, root: ObjectRef, mem: *Self, depth: usize, nodes_per_layer: usize) !void {
            try cur.set(0, Type.from(root));
            if (depth == 0) return; // no more layers to add
            for (0..nodes_per_layer) |i| {
                const child = mem.alloc_struct();
                try cur.set(i + 1, Type.from(child));

                // make sure only reference to child is from `cur`
                child.decr();

                try buildTree(child, root, mem, depth - 1, nodes_per_layer);
            }
        }
    };

    const layers = 6;
    const nodes_per_layer = 5;

    // geometric series
    // around 19K nodes with layers=6 and nodes_per_layer=5
    const expected_node_count = (try std.math.powi(usize, nodes_per_layer, layers + 1) - 1) / (nodes_per_layer - 1);

    const root = memoryManager.alloc_struct();
    try utils.buildTree(root, root, &memoryManager, layers, nodes_per_layer);

    // add some random references throughout the tree
    var rand = std.rand.DefaultPrng.init(0);
    for (0..expected_node_count) |i| {
        const j = rand.random().intRangeLessThan(usize, 0, expected_node_count);
        const ref1 = ObjectRef{ .ref = memoryManager.allObjects.items[i] };
        const ref2 = ObjectRef{ .ref = memoryManager.allObjects.items[j] };
        try ref1.set(nodes_per_layer + 1, Type.from(ref2));
    }

    try std.testing.expectEqual(expected_node_count, memoryManager.get_object_count());

    // drop the entire tree
    root.decr();
    try memoryManager.gc_pass();

    try std.testing.expectEqual(0, memoryManager.get_object_count());
}
