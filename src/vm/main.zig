const std = @import("std");
const types = @import("types.zig");

pub fn main() void {
    std.debug.print("Hello from VM! {}\n", .{types.R});
}
