//!
//! Internal types of vm
//!

const std = @import("std");
const builtin = @import("builtin");
const memory_manager = @import("memory_manager");

const ListRef = memory_manager.APITypes.ListRef;
const ObjectRef = memory_manager.APITypes.ObjectRef;

pub const UnitType = packed struct {
    const Self = @This();
    pub fn init() Self {
        return .{};
    }
};

pub const Type = union(enum) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);
    unit: UnitType,
    int: i64,
    float: f64,
    list: ListRef,
    object: ObjectRef,

    pub fn GetRepr(comptime E: Type.Tag) type {
        return switch (E) {
            .unit => UnitType,
            .int => i64,
            .float => f64,
            .list => ListRef,
            .object => ObjectRef,
        };
    }

    pub fn clone(self: *const Self) Self {
        var res = self.*;
        switch (res) {
            .list => |*m| m.incr(),
            .object => |*m| m.incr(),
            else => {},
        }
        return res;
    }

    pub fn deinit(self: *const Self) void {
        switch (self.tag()) {
            .list => self.list.decr(),
            .object => self.object.decr(),
            else => {},
        }
    }

    pub fn tag(self: *const Self) Tag {
        return @as(Tag, self.*);
    }

    pub fn from(x: anytype) Self {
        const T = @TypeOf(x);

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

        return switch (@typeInfo(T)) {
            .Int, .ComptimeInt => .{ .int = @intCast(x) },

            .Float, .ComptimeFloat => .{ .float = @floatCast(x) },

            else => @compileError(std.fmt.comptimePrint(
                "'{s}' not an int, float, Object, or List\n",
                .{@typeName(T)},
            )),
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
        if (builtin.mode == .Debug and !self.is(T)) {
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
            .list => |c| if (T == .list) c else unreachable,
            .object => |c| if (T == .object) c else unreachable,
        };
    }

    pub fn format(self: *const Self, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try switch (self.*) {
            .unit => writer.print("()", .{}),
            .int => |i| writer.print("{}", .{i}),
            .float => |f| writer.print("{d}", .{f}),
            else => @panic("unimplemented"), // TODO: implement formatting for lists and objects
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

    try comptime std.testing.expect(std.mem.eql(u8, "0", std.fmt.comptimePrint("{}", .{Type.from(0)})));
    try comptime std.testing.expect(std.mem.eql(u8, "0", std.fmt.comptimePrint("{}", .{Type.from(0.0)})));
}
