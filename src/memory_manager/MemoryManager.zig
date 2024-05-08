const Self = @This();
const std = @import("std");
const APITypes = @import("APITypes.zig");
const ObjectRef = APITypes.ObjectRef;
const ListRef = APITypes.ListRef;
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;
const Stack = std.ArrayList(APITypes.Type);

fn UnmanagedObjectList(comptime T: type) type {
    return std.ArrayListUnmanaged(*T);
}

allocator: std.mem.Allocator,
allObjects: UnmanagedObjectList(Object),
allLists: UnmanagedObjectList(List),
stack: *Stack,

pub fn init(allocator: std.mem.Allocator, stack: *Stack) !Self {
    return Self{
        .allocator = allocator,
        .allObjects = try UnmanagedObjectList(Object).initCapacity(allocator, 0),
        .allLists = try UnmanagedObjectList(List).initCapacity(allocator, 0),
        .stack = stack,
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
        .object => |*obj| {
            if (!obj.ref.refs.mark) {
                obj.ref.refs.mark = true;
                var it = obj.ref.map.valueIterator();
                while (it.next()) |inner_item| {
                    mark_item(inner_item);
                }
            }
        },
        .list => |*list| {
            if (!list.ref.refs.mark) {
                list.ref.refs.mark = true;
                for (list.ref.items.items) |*inner_item| {
                    mark_item(inner_item);
                }
            }
        },
        else => {},
    }
}

/// Remove all objects that have a refcount of 0, but do not deinit them.
/// Objects with a refcount of 0 are assumed to already have been deinitialized.
/// This function simply removes them from the internal array storing objects.
fn remove_unreachable_references(self: *Self, comptime T: type, list: *UnmanagedObjectList(T)) !void {
    // Mark all objects as false
    for (list.items) |obj| {
        obj.refs.mark = false;
    }

    // Mark roots (objects on the stack)
    for (self.stack.items) |*item| {
        // TODO only mark if type is T.
        mark_item(item);
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
        if (obj.refs.mark) {
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

/// Remove an obj from the stack.
///
/// For testing.
fn remove(stack: *Stack, obj: APITypes.ObjectRef) void {
    // TODO there might be a better way to do this...
    for (stack.items, 0..) |item, index| {
        switch (item) {
            .object => |obj2| {
                if (obj.ref == obj2.ref) {
                    _ = stack.orderedRemove(index);
                    return;
                }
            },
            else => {},
        }
    }
    @panic("Unable to find object to remove.");
}

test "get and set to struct" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectRef = memoryManager.alloc_struct();

    try objectRef.set(123, Type.from(456));

    try std.testing.expectEqual(456, objectRef.get(123).?.int);
}

test "get and set to list" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var listRef = memoryManager.alloc_list();

    try listRef.push(Type.from(123));

    try std.testing.expectEqual(1, listRef.length());
    try std.testing.expectEqual(123, listRef.get(0).int);
}

test "run gc pass with empty memory manager" {
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    try memoryManager.gc_pass();
}

test "gc pass removes one unused object" {
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    // Do not put object on stack.
    _ = memoryManager.alloc_struct();
    try std.testing.expectEqual(1, memoryManager.get_object_count());

    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "gc pass keeps one object still in use" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    const objectRef = memoryManager.alloc_struct();
    try stack.append(Type.from(objectRef));

    try std.testing.expectEqual(1, memoryManager.get_object_count());

    try memoryManager.gc_pass();
    try std.testing.expectEqual(1, memoryManager.get_object_count());
}

test "gc pass keeps one object still in use and discards one unused" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    _ = memoryManager.alloc_struct();

    try stack.append(Type.from(objectRef1));
    try objectRef1.set(123, Type.from(456));

    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // objectRef2 is not on the stack
    try memoryManager.gc_pass();

    try std.testing.expectEqual(1, memoryManager.get_object_count());
    try std.testing.expectEqual(456, objectRef1.get(123).?.int);
}

test "assign object to object" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectRef1 = memoryManager.alloc_struct();
    var objectRef2 = memoryManager.alloc_struct();
    try objectRef1.set(123, Type.from(456));
    try objectRef2.set(123, Type.from(objectRef1));
    try std.testing.expectEqual(2, memoryManager.get_object_count());
}

test "object in object, drop parent, keep child" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type.from(456)); // A[123] = 456
    try objectB.set(123, Type.from(objectA)); // B[123] = A

    try stack.append(Type.from(objectA));
    try stack.append(Type.from(objectB));
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop object B from stack. The child A should still be kept since it
    remove(&stack, objectB);
    // Object B should be dropped
    try memoryManager.gc_pass();
    // Only Object A should be alive.
    try std.testing.expectEqual(1, memoryManager.get_object_count());

    try std.testing.expectEqual(456, objectA.get(123).?.int);
}

test "object in object, drop child from stack, gc, both stay" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(123, Type.from(456)); // A[123] = 456
    try objectB.set(123, Type.from(objectA)); // B[123] = A

    try stack.append(Type.from(objectA));
    try stack.append(Type.from(objectB));
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop object A from stack. It should still be kept since it is alive as a child of object B.
    remove(&stack, objectA);
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());
}

test "cycles get dropped" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    var objectB = memoryManager.alloc_struct(); // B
    try objectA.set(124, Type.from(objectA)); // A[124] = B
    try objectB.set(123, Type.from(objectA)); // B[123] = A

    try stack.append(Type.from(objectA));
    try stack.append(Type.from(objectB));
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    // Drop both from stack.
    // They should both
    remove(&stack, objectA);
    remove(&stack, objectB);
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "one object refers to same object twice" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    const objectB = memoryManager.alloc_struct(); // B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    try objectA.set(1, Type.from(objectB)); // A[1] = B
    // all references to B are from A

    try stack.append(Type.from(objectA));
    try stack.append(Type.from(objectB));
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    remove(&stack, objectA);
    remove(&stack, objectB);
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "object key set twice with same value" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objectA = memoryManager.alloc_struct(); // A
    const objectB = memoryManager.alloc_struct(); // B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    try objectA.set(0, Type.from(objectB)); // A[0] = B
    // all references to B are from A

    try stack.append(Type.from(objectA));
    try stack.append(Type.from(objectB));
    try memoryManager.gc_pass();
    try std.testing.expectEqual(2, memoryManager.get_object_count());

    remove(&stack, objectA);
    remove(&stack, objectB);
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "big cycle" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
    defer memoryManager.deinit();

    var objects = std.ArrayList(ObjectRef).init(std.testing.allocator);
    defer objects.deinit();

    const cycle_len = 128;

    for (0..cycle_len) |_| {
        const objectRef = memoryManager.alloc_struct();
        try objects.append(objectRef);
        try stack.append(Type.from(objectRef));
    }

    for (0..cycle_len) |i| {
        try objects.items[(i + 1) % cycle_len].set(0, Type.from(objects.items[i]));
    }

    try memoryManager.gc_pass();
    try std.testing.expectEqual(cycle_len, memoryManager.get_object_count());

    stack.clearAndFree();
    try memoryManager.gc_pass();
    try std.testing.expectEqual(0, memoryManager.get_object_count());
}

test "tree of objects with references to root" {
    const Type = APITypes.Type;
    var stack = Stack.init(std.testing.allocator);
    defer stack.deinit();
    var memoryManager = try Self.init(std.testing.allocator, &stack);
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
