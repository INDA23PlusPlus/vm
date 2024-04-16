//!
//! Exposed types from memory manager for use in VM
//!
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;
const InternalType = types.Type;
const KeyIterator = @import("std").AutoHashMap(usize, void).KeyIterator;

pub const ListRef = struct {
    const Self = @This();
    ref: *List,

    pub fn incr(self: *const Self) void {
        _ = self.ref.refcount.increment();
    }

    pub fn decr(self: *const Self) void {
        _ = self.ref.refcount.decrement();
    }

    pub fn length(self: *Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *Self, index: usize) ?Type {
        return Type.from(&self.ref.items.items[index]);
    }

    pub fn set(self: *Self, key: usize, value: Type) void {
        self.ref.items.items[key] = value.to_internal();
    }

    pub fn push(self: *Self, value: Type) !void {
        try self.ref.items.append(value.to_internal());
    }
};

pub const ObjectRef = struct {
    const Self = @This();
    ref: *Object,

    pub fn incr(self: *const Self) void {
        _ = self.ref.incr();
    }

    pub fn decr(self: *const Self) void {
        _ = self.ref.decr();
    }

    pub fn get(self: *Self, key: u32) ?Type {
        var val = self.ref.map.get(key);
        if (val == null) {
            return null;
        }
        return Type.from(&val.?);
    }

    pub fn set(self: *Self, key: u32, value: Type) !void {
        try self.ref.map.put(key, value.to_internal());
    }

    pub fn keys(self: *Self) KeyIterator {
        return self.ref.map.keyIterator();
    }
};

pub const Type = union(enum) {
    unit: @TypeOf(.{}),
    int: i64,
    float: f64,
    list: ListRef,
    object: ObjectRef,

    const Self = @This();

    pub fn from(internal: *InternalType) Type {
        return switch (internal.*) {
            InternalType.unit => Type{ .unit = .{} },
            InternalType.list => |*val| Type{ .list = ListRef{ .ref = val } },
            InternalType.object => |*val| Type{ .object = ObjectRef{ .ref = val } },
            InternalType.int => Type{ .int = internal.int },
            InternalType.float => Type{ .float = internal.float },
        };
    }

    pub fn to_internal(self: Self) InternalType {
        return switch (self) {
            Type.unit => InternalType{ .unit = .{} },
            Type.list => |*val| InternalType{ .list = val.ref.* },
            Type.object => |*val| InternalType{ .object = val.ref.* },
            Type.int => InternalType{ .int = self.int },
            Type.float => InternalType{ .float = self.float },
        };
    }
};
