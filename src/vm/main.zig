const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMInstruction = @import("VMInstruction.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    std.debug.print("program result: {}\n", .{try Interpreter.run(
        &.{
            VMInstruction.push(2),
            VMInstruction.push(1),
            VMInstruction.greater(),
        },
        gpa.allocator(),
        std.io.getStdOut().writer(),
        true,
    )});
    // std.debug.print("Hello from VM!\n", .{});
}
