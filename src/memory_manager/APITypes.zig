//!
//! Exposed types from memory manager for use in VM
//!
const std = @import("std");
const Type = @import("arch").Type;
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

    pub fn deinit(self: *const Self) void {
        _ = self;
    }

    // DEPRECATED Increment the reference count, called when a new reference is created (e.g. copy)
    pub fn incr(self: *const Self) void {
        _ = self;
    }

    //  DEPRECATED Decrement the reference count, called when a reference is destroyed (e.g. deinit)
    pub fn decr(self: *const Self) void {
        _ = self;
    }

    pub fn length(self: *const Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) Value {
        if (index >= self.length()) {
            return Value.from(Unit.init());
        } else {
            return self.ref.items.items[index];
        }
    }

    pub fn set(self: *const Self, index: usize, value: Value) void {
        if (index >= self.ref.items.items.len) {
            for (0..index - self.ref.items.items.len) |_| {
                self.ref.items.append(Value.from(Unit.init())) catch |err| {
                    std.debug.print("Error on list set: {}\n", .{err});
                    return;
                };
            }
            self.ref.items.append(value) catch |err| {
                std.debug.print("Error on list set: {}\n", .{err});
                return;
            };
            return;
        }
        self.ref.items.items[index] = value;
    }

    pub fn push(self: *const Self, value: Value) !void {
        try self.ref.items.append(value);
    }

    pub fn pop(self: *const Self) Value {
        return self.ref.items.pop();
    }

    pub fn remove(self: *const Self, index: usize) !void {
        // TODO: error on OOB index?
        for (index..self.ref.items.items.len - 1) |i| {
            self.ref.items.items[i] = self.ref.items.items[i + 1];
        }
        _ = self.ref.items.pop();
    }

    pub fn concat(self: *const Self, other: *const Self) !void {
        try self.ref.items.appendSlice(other.ref.items.items);
    }
};

pub const ObjectRef = struct {
    const Self = @This();
    ref: *Object,

    // Initialize the list
    pub fn init(allocator: std.mem.Allocator) !Self {
        const obj = try allocator.create(Object);
        obj.* = Object.init(allocator);
        return .{ .ref = obj };
    }

    pub fn deinit(self: *const Self) void {
        _ = self;
    }

    //  DEPRECATED Increment the reference count, called when a new reference is created (e.g. copy)
    pub fn incr(self: *const Self) void {
        _ = self;
    }

    //  DEPRECATED Decrement the reference count, called when a reference is destroyed (e.g. deinit)
    pub fn decr(self: *const Self) void {
        _ = self;
    }

    pub fn get(self: *const Self, key: usize) ?Value {
        const val = self.ref.map.get(key);
        if (val == null) {
            return null;
        }
        return val;
    }

    pub fn set(self: *const Self, key: usize, value: Value) !void {
        try self.ref.map.put(key, value);
    }

    pub fn keys(self: *const Self) @TypeOf(self.ref.map.keyIterator()) {
        return self.ref.map.keyIterator();
    }

    pub fn values(self: *const Self) @TypeOf(self.ref.map.valueIterator()) {
        return self.ref.map.valueIterator();
    }

    pub fn entries(self: *const Self) @TypeOf(self.ref.map.iterator()) {
        return self.ref.map.iterator();
    }
};

const StringLit = *const []const u8;

const StringRef = struct {
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

const String = union(enum) {
    string_lit: StringLit,
    string_ref: StringRef,
};

pub const Unit = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }
};

// assert that @intFromEnum(e1) ^ @intFromEnum(e2) is equivalent to checking if comparisons are allowed between these types
comptime {
    for ([_]Type{
        .int,
        .float,
        .unit,
        .string,
        .list,
        .object,
    }) |e1| {
        for ([_]Type{
            .int,
            .float,
            .unit,
            .string,
            .list,
            .object,
        }) |e2| {
            // should only happen on valid comparisons
            if (@intFromEnum(e1) ^ @intFromEnum(e2) < 2) {
                // should only be valid if one is int and one is float, or both are some kind of string
                if (e1 != e2) {
                    const int_float = (e1 == .int and e2 == .float) or (e1 == .float and e2 == .int);
                    std.debug.assert(int_float);
                }
            }
        }
    }
}

pub const Value = union(Type) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);

    unit: Unit,
    int: i64,
    float: f64,
    string: String,
    list: ListRef,
    object: ObjectRef,

    pub fn GetRepr(comptime E: Value.Tag) type {
        return switch (E) {
            .unit => Unit,
            .int => i64,
            .float => f64,
            .string => String,
            .list => ListRef,
            .object => ObjectRef,
        };
    }

    pub fn incr(self: *const Self) void {
        @setCold(true);
        switch (self.*) {
            .string => |string| {
                switch (string) {
                    .string_ref => |*m| m.incr(),
                    else => {},
                }
            },
            .list => |*m| m.incr(),
            .object => |*m| m.incr(),
            else => {},
        }
    }

    pub fn decr(self: *const Self) void {
        @setCold(true);
        switch (self.*) {
            .string => |string| {
                switch (string) {
                    .string_ref => |*m| m.decr(),
                    else => {},
                }
            },
            .list => |*m| m.decr(),
            .object => |*m| m.decr(),
            else => {},
        }
    }

    pub fn clone(self: *const Self) Self {
        if (@intFromEnum(self.tag()) > 2) {
            self.incr();
        }
        return self.*;
    }

    pub fn deinit(self: *const Self) void {
        if (@intFromEnum(self.tag()) > 2) {
            self.decr();
        }
    }

    pub fn tag(self: *const Self) Tag {
        return @as(Tag, self.*);
    }

    fn from_(x: anytype) Self {
        const T = @TypeOf(x);

        return switch (T) {
            Value => x,
            String => return .{ .string = x },
            StringLit => return .{ .string = .{ .string_lit = x } },
            StringRef => return .{ .string = .{ .string_ref = x } },
            ListRef => .{ .list = x },
            ObjectRef => .{ .object = x },
            Unit => .{ .unit = x },
            void => .{ .unit = .{} },
            else => switch (@typeInfo(T)) {
                .Bool => .{ .int = @intFromBool(x) },
                .Int, .ComptimeInt => .{ .int = @intCast(x) },
                .Float, .ComptimeFloat => .{ .float = @floatCast(x) },
                else => @compileError(std.fmt.comptimePrint(
                    "'{s}' not convertible to Value\n",
                    .{@typeName(T)},
                )),
            },
        };
    }

    pub fn tryFrom(x: anytype) !Self {
        return from(try x);
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
        Value.from(0).as(.int).? == 0,
    );
    try std.testing.expect(
        Value.from(0.0).as(.float).? == 0.0,
    );
    try std.testing.expect(
        Value.from(0).as(.float) == null,
    );
    try std.testing.expect(
        Value.from(0.0).as(.int) == null,
    );
    try std.testing.expectEqual(
        Unit.init(),
        Value.from(Unit.init()).as(.unit),
    );
}
