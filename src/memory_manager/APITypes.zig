//!
//! Exposed types from memory manager for use in VM
//!
const std = @import("std");
const types = @import("types.zig");
const Object = types.Object;
const List = types.List;
const InternalType = types.Type;

pub const ListRef = struct {
    const Self = @This();
    ref: *List,

    pub fn incr(self: *const Self) void {
        _ = self.ref.refcount.increment();
    }

    pub fn decr(self: *const Self) void {
        _ = self.ref.refcount.decrement();
    }

    pub fn length(self: *const Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) ?Type {
        return Type.fromInternal(&self.ref.items.items[index]);
    }

    pub fn set(self: *const Self, key: usize, value: Type) void {
        self.ref.items.items[key] = value.toInternal();
    }

    pub fn push(self: *const Self, value: Type) !void {
        try self.ref.items.append(value.toInternal());
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

    pub fn get(self: *const Self, key: usize) ?Type {
        var val = self.ref.map.get(key);
        if (val == null) {
            return null;
        }
        return Type.fromInternal(&val.?);
    }

    pub fn set(self: *const Self, key: usize, value: Type) !void {
        try self.ref.map.put(key, value.toInternal());
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

    pub fn fromInternal(internal: *InternalType) Type {
        return switch (internal.*) {
            .unit => Type{ .unit = .{} },
            .list => |*val| Type{ .list = ListRef{ .ref = val } },
            .object => |*val| Type{ .object = ObjectRef{ .ref = val } },
            .int => Type{ .int = internal.int },
            .float => Type{ .float = internal.float },
        };
    }

    pub fn toInternal(self: Self) InternalType {
        return switch (self) {
            .unit => InternalType{ .unit = .{} },
            .list => |*val| InternalType{ .list = val.ref.* },
            .object => |*val| InternalType{ .object = val.ref.* },
            .int => InternalType{ .int = self.int },
            .float => InternalType{ .float = self.float },
            .string => @panic("unimplemented"),
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

    {
        var t = Type.from(0);
        var internal = Type.toInternal(t);
        try std.testing.expectEqual(t.as(.int), Type.fromInternal(&internal).as(.int));
    }
}
