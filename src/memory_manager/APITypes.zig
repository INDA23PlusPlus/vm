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
        self.ref.decr();
    }

    pub fn length(self: *const Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) Type {
        if (index >= self.length()) {
            return Type.from(UnitType.init());
        } else {
            return self.ref.items.items[index];
        }
    }

    pub fn set(self: *const Self, index: usize, value: Type) void {
        if (index >= self.ref.items.items.len) {
            for (0..index - self.ref.items.items.len) |_| {
                self.ref.items.append(Type.from(UnitType.init())) catch |err| {
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
        self.ref.decr();
    }

    pub fn get(self: *const Self, key: usize) ?Type {
        const val = self.ref.map.get(key);
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

    pub fn values(self: *const Self) @TypeOf(self.ref.map.valueIterator()) {
        return self.ref.map.valueIterator();
    }

    pub fn entries(self: *const Self) @TypeOf(self.ref.map.iterator()) {
        return self.ref.map.iterator();
    }
};

const StringLit = *const []const u8;
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
};

pub const TypeEnum = enum(u8) {
    // zig fmt: off
    unit       = 0b0010,

    int        = 0b0000,
    float      = 0b0001,

    string_lit = 0b10000,
    string_ref = 0b10001,

    list       = 0b1010,
    object     = 0b1100,
    // zig fmt: on
};

// assert that @intFromEnum(e1) ^ @intFromEnum(e2) is equivalent to checking if comparisons are equivalent
comptime {
    for ([_]TypeEnum{
        .int,
        .float,
        .unit,
        .string_lit,
        .string_ref,
        .list,
        .object,
    }) |e1| {
        for ([_]TypeEnum{
            .int,
            .float,
            .unit,
            .string_lit,
            .string_ref,
            .list,
            .object,
        }) |e2| {
            // should only happen on valid comparisons
            if (@intFromEnum(e1) ^ @intFromEnum(e2) < 2) {
                // should only be valid if one is int and one is float
                if (e1 != e2) {
                    std.debug.assert((e1 == .int and e2 == .float) or (e1 == .float and e2 == .int) or (e1 == .string_lit and e2 == .string_ref) or (e1 == .string_ref and e2 == .string_lit));
                }
            }
        }
    }
}

pub const Type = union(TypeEnum) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);

    unit: UnitType,
    int: i64,
    float: f64,
    string_lit: StringLit,
    string_ref: StringRef,
    list: ListRef,
    object: ObjectRef,

    pub fn GetRepr(comptime E: Type.Tag) type {
        return switch (E) {
            .unit => UnitType,
            .int => i64,
            .float => f64,
            .string_lit => StringLit,
            .string_ref => StringRef,
            .list => ListRef,
            .object => ObjectRef,
        };
    }

    pub fn clone(self: *const Self) Self {
        var res = self.*;
        switch (res) {
            .string_ref => |*m| m.incr(),
            .list => |*m| m.incr(),
            .object => |*m| m.incr(),
            else => {},
        }
        return res;
    }

    pub fn deinit(self: *const Self) void {
        switch (self.tag()) {
            .string_ref => self.string_ref.decr(),
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

        return switch (T) {
            Type => x,
            StringLit => return .{ .string_lit = x },
            StringRef => return .{ .string_ref = x },
            ListRef => .{ .list = x },
            ObjectRef => .{ .object = x },
            UnitType => .{ .unit = x },
            void => .{ .unit = .{} },
            else => switch (@typeInfo(T)) {
                .Bool => .{ .int = @intFromBool(x) },
                .Int, .ComptimeInt => .{ .int = @intCast(x) },
                .Float, .ComptimeFloat => .{ .float = @floatCast(x) },
                else => @compileError(std.fmt.comptimePrint(
                    "'{s}' not convertible to Type\n",
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
            .string_lit => |c| if (T == .string_lit) c else unreachable,
            .string_ref => |c| if (T == .string_ref) c else unreachable,
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
