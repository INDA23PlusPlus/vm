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

    pub fn init(allocator: std.mem.Allocator) !Self {
        const list = try allocator.create(List);
        list.* = List.init(allocator);
        return .{ .ref = list };
    }

    pub fn deinit(self: *const Self) void {
        _ = self;
    }

    pub fn length(self: *const Self) usize {
        return self.ref.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) Value {
        if (index >= self.length()) {
            return Value.from(Unit{});
        } else {
            return self.ref.items.items[index];
        }
    }

    pub fn set(self: *const Self, index: usize, value: Value) void {
        if (index >= self.ref.items.items.len) {
            for (0..index - self.ref.items.items.len) |_| {
                self.ref.items.append(Value.from(Unit{})) catch |err| {
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

    pub fn get(self: *const Self) []const u8 {
        _ = self;
        return "";
    }
};

pub const Unit = void;

comptime {
    std.debug.assert(@sizeOf(Value) == 16);
}

pub const Value = union(Type) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);

    unit: Unit,
    int: i64,
    float: f64,
    string_ref: StringRef,
    string_lit: StringLit,
    list: ListRef,
    object: ObjectRef,

    pub fn TagFromType(comptime T: type) ?Value.Tag {
        return switch (T) {
            StringLit => .string_lit,
            StringRef => .string_ref,
            ListRef => .list,
            ObjectRef => .object,
            else => switch (@typeInfo(T)) {
                .Bool, .Int, .ComptimeInt => .int,
                .Float, .ComptimeFloat => .float,
                else => null,
            },
        };
    }

    pub fn GetRepr(comptime E: Value.Tag) type {
        return switch (E) {
            .unit => Unit,
            .int => i64,
            .float => f64,
            .string_lit => StringLit,
            .string_ref => StringRef,
            .list => ListRef,
            .object => ObjectRef,
        };
    }

    pub fn tag(self: *const Self) Tag {
        return @as(Tag, self.*);
    }

    fn from_(x: anytype) Self {
        const T = @TypeOf(x);

        return switch (T) {
            Value => x,
            StringLit => return .{ .string_lit = x },
            StringRef => return .{ .string_ref = x },
            ListRef => .{ .list = x },
            ObjectRef => .{ .object = x },
            Unit => .{ .unit = x },
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
        return switch (@typeInfo(@TypeOf(x))) {
            .Optional => if (x == null)
                from_(void{})
            else
                from_(x.?),
            else => from_(x),
        };
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
            .string_ref => |c| if (T == .string_ref) c else unreachable,
            .string_lit => |c| if (T == .string_lit) c else unreachable,
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
        Unit{},
        Value.from(Unit{}).as(.unit),
    );
}
