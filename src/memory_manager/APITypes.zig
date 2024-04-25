//!
//! Exposed types from memory manager for use in VM
//!
const std = @import("std");
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;

pub const ListRef = struct {
    const Self = @This();
    ref: *List,

    // Initialize the list, refcount is 1
    pub fn init(allocator: std.mem.Allocator) !Self {
        const list = try allocator.create(List);
        list.* = List.init(allocator);
        return .{ .ref = list };
    }

    // Copy the reference to the list, incrementing the reference count
    pub fn copy(self: *const Self) Self {
        self.incr();
        return .{ .ref = self.ref };
    }

    // Assign a new reference to the list, decrementing the reference count of the old list
    // and incrementing the reference count of the new list
    pub fn assign(self: *const Self, other: Self) void {
        // It is important to increment the reference count of the new list before decrementing the old list
        // Otherwise the refcount could reach 0 and the object could be deallocated if other is the same as self
        other.incr();
        self.decr();
        self.ref = other.ref;
    }

    // Deinitialize the list, decrementing the reference count
    pub fn deinit(self: *const Self) void {
        self.decr();
    }

    // Increment the reference count, called when a new reference is created (e.g. copy)
    pub fn incr(self: *const Self) void {
        _ = self.ref.incr();
    }

    // Decrement the reference count, called when a reference is destroyed (e.g. deinit)
    pub fn decr(self: *const Self) void {
        _ = self.ref.decr();
    }

    pub fn length(self: *const Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) Type {
        return self.ref.items.items[index];
    }

    pub fn set(self: *const Self, key: usize, value: Type) void {
        var old = self.ref.items.items[key];
        // Decrement old count
        switch (old) {
            .object => |obj| {
                obj.decr();
            },
            .list => |obj| {
                obj.decr();
            },
        }
        // Increment new count
        switch (value) {
            .object => |obj| {
                obj.incr();
            },
            .list => |obj| {
                obj.incr();
            },
        }
        self.ref.items.items[key] = value;
    }

    pub fn push(self: *const Self, value: Type) !void {
        try self.ref.items.append(value);
    }
};

pub const ObjectRef = struct {
    const Self = @This();
    ref: *Object,

    // Initialize the list, refcount is 1
    pub fn init(allocator: std.mem.Allocator) !Self {
        const obj = try allocator.create(Object);
        obj.* = Object.init(allocator);
        return .{ .ref = obj };
    }

    // Copy the reference to the list, incrementing the reference count
    pub fn copy(self: *const Self) Self {
        self.incr();
        return .{ .ref = self.ref };
    }

    // Assign a new reference to the list, decrementing the reference count of the old list
    // and incrementing the reference count of the new list
    pub fn assign(self: *const Self, other: Self) void {

        // It is important to increment the reference count of the new list before decrementing the old list
        // Otherwise the refcount could reach 0 and the object could be deallocated if other is the same as self
        other.incr();
        self.decr();
        self.ref = other.ref;
    }

    // Deinitialize list, decrementing the reference count
    pub fn deinit(self: *const Self) void {
        self.decr();
    }

    // Increment the reference count, called when a new reference is created (e.g. copy)
    pub fn incr(self: *const Self) void {
        _ = self.ref.incr();
    }

    // Decrement the reference count, called when a reference is destroyed (e.g. deinit)
    pub fn decr(self: *const Self) void {
        _ = self.ref.decr();
    }

    pub fn get(self: *const Self, key: usize) ?Type {
        var val = self.ref.map.get(key);
        if (val == null) {
            return null;
        }
        return val;
    }

    pub fn set(self: *const Self, key: usize, value: Type) !void {
        try self.ref.map.put(key, value);
    }

    pub fn keys(self: *const Self) @TypeOf(self.ref.map.keyIterator()) {
        return self.ref.map.keyIterator();
    }
};

const StringLit = []const u8;
const StringRef = struct {
    // TODO: memory_manager.APITypes.StringRef
    const Self = @This();

    pub fn incr(self: *const Self) void {
        _ = self;
    }

    pub fn decr(self: *const Self) void {
        _ = self;
    }

    pub fn get(self: *const Self) []const u8 {
        _ = self;
        return "";
    }
};

pub const UnitType = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn incr(self: *const Self) void {
        _ = self;
    }

    pub fn decr(self: *const Self) void {
        _ = self;
    }
};

const String = union(enum) {
    // Common string type, can be either a string slice or a reference to a dynamic string
    const Self = @This();

    lit: StringLit,
    ref: StringRef,

    pub fn incr(self: *const Self) void {
        switch (self.*) {
            .lit => {},
            .ref => self.ref.incr(),
        }
    }

    pub fn decr(self: *const Self) void {
        switch (self.*) {
            .lit => {},
            .ref => self.ref.decr(),
        }
    }

    pub fn get(self: *const Self) []const u8 {
        switch (self.*) {
            .lit => return self.lit,
            .ref => return self.ref.get(),
        }
    }

    pub fn from(x: anytype) Self {
        switch (@TypeOf(x)) {
            StringLit => return .{ .lit = x },
            StringRef => return .{ .ref = x },
            else => @compileError(std.fmt.comptimePrint("type {} is not convertible to String", .{x})),
        }
    }
};

pub const Type = union(enum) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);
    unit: UnitType,
    int: i64,
    float: f64,
    string: String,
    list: ListRef,
    object: ObjectRef,

    pub fn GetRepr(comptime E: Type.Tag) type {
        return switch (E) {
            .unit => UnitType,
            .int => i64,
            .float => f64,
            .string => String,
            .list => ListRef,
            .object => ObjectRef,
        };
    }

    pub fn clone(self: *const Self) Self {
        var res = self.*;
        switch (res) {
            .string => |*m| m.incr(),
            .list => |*m| m.incr(),
            .object => |*m| m.incr(),
            else => {},
        }
        return res;
    }

    pub fn deinit(self: *const Self) void {
        switch (self.tag()) {
            .string => self.string.decr(),
            .list => self.list.decr(),
            .object => self.object.decr(),
            else => {},
        }
    }

    pub fn tag(self: *const Self) Tag {
        return @as(Tag, self.*);
    }

    fn from_(x: anytype) Self {
        const T = @TypeOf(x);

        if (T == Type) {
            return x.clone();
        }
        if (T == StringLit or T == StringRef) {
            var res = .{ .string = String.from(x) };
            res.string.incr();
            return res;
        }
        if (T == ListRef) {
            var res = .{ .list = x };
            res.list.incr();
            return res;
        }
        if (T == ObjectRef) {
            var res = .{ .object = x };
            res.object.incr();
            return res;
        }
        if (T == UnitType) {
            return .{ .unit = x };
        }
        if (T == void) {
            return .{ .unit = .{} };
        }

        return switch (@typeInfo(T)) {
            .Int, .ComptimeInt => .{ .int = @intCast(x) },

            .Float, .ComptimeFloat => .{ .float = @floatCast(x) },

            else => @compileError(std.fmt.comptimePrint(
                "'{s}' not convertible to Type\n",
                .{@typeName(T)},
            )),
        };
    }

    pub fn from(x: anytype) Self {
        switch (@typeInfo(@TypeOf(x))) {
            .Optional => {
                if (x == null) {
                    return from_(void{});
                } else {
                    return from_(x.?);
                }
            },
            else => {
                return from_(x);
            },
        }
    }

    /// returns whether the active member of `self` is of type `T`
    pub fn is(self: *const Self, comptime T: Tag) bool {
        return self.tag() == T;
    }

    /// returns the active member of `self` if it is of type `T`, else `null`
    pub fn as(self: *const Self, comptime T: Tag) ?GetRepr(T) {
        return if (self.is(T)) self.asUnChecked(T) else null;
    }

    /// UB if `!self.is(T)`
    pub fn asUnChecked(self: *const Self, comptime T: Tag) GetRepr(T) {
        // check anyway if in debug mode
        if (std.debug.runtime_safety and !self.is(T)) {
            std.debug.panic("was supposed to be {s} but was {s}", .{
                @tagName(T),
                @tagName(self.*),
            });
        }

        // kinda horrible but what can you do
        return switch (self.*) {
            .unit => |c| if (T == .unit) c else unreachable,
            .int => |c| if (T == .int) c else unreachable,
            .float => |c| if (T == .float) c else unreachable,
            .string => |c| if (T == .string) c else unreachable,
            .list => |c| if (T == .list) c else unreachable,
            .object => |c| if (T == .object) c else unreachable,
        };
    }
};

test "casting" {
    try std.testing.expect(
        Type.from(0).as(.int).? == 0,
    );
    try std.testing.expect(
        Type.from(0.0).as(.float).? == 0.0,
    );
    try std.testing.expect(
        Type.from(0).as(.float) == null,
    );
    try std.testing.expect(
        Type.from(0.0).as(.int) == null,
    );
    try std.testing.expectEqual(
        UnitType.init(),
        Type.from(UnitType.init()).as(.unit),
    );
}
