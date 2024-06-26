const std = @import("std");

const Self = @This();

/// Creates a comptime map from enum tag names to enum values.
pub fn TagNameMap(comptime T: type) std.StaticStringMap(T) {
    if (@typeInfo(T) != .Enum) {
        @compileError("T must be an enum");
    }

    return std.StaticStringMap(T).initComptime(create: {
        const KV = struct { []const u8, T };
        var array: [std.meta.tags(T).len]KV = undefined;
        inline for (0.., std.meta.tags(T)) |i, tag| {
            array[i] = .{ @tagName(tag), tag };
        }
        break :create array;
    });
}

test TagNameMap {
    const TestEnum = enum { yes, no };
    const map = TagNameMap(TestEnum);

    try std.testing.expectEqual(map.get("yes"), TestEnum.yes);
    try std.testing.expectEqual(map.get("no"), TestEnum.no);
    try std.testing.expectEqual(map.get("maybe"), null);
}
