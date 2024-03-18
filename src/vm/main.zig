const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMInstruction = @import("VMInstruction.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    try Interpreter.run(
        &.{
            VMInstruction.push(0),
            VMInstruction.pop(),
        },
        gpa.allocator(),
    );
    // std.debug.print("Hello from VM!\n", .{});
}
