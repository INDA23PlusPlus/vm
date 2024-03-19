const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMInstruction = @import("VMInstruction.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    try Interpreter.run(
        &.{
            VMInstruction.push(1),
            VMInstruction.push(2),
            VMInstruction.sub(),
            VMInstruction.pop(),
        },
        gpa.allocator(),
    );
    // std.debug.print("Hello from VM!\n", .{});
}
