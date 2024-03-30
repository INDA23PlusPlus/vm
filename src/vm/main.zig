const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMContext = @import("VMContext.zig");
const VMInstruction = @import("VMInstruction.zig");
const VMProgram = @import("VMProgram.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const prog = VMProgram.init(&.{
        VMInstruction.push(2),
        VMInstruction.push(1),
        VMInstruction.greater(),
    }, 0);
    var ctxt = VMContext.init(prog, gpa.allocator(), std.io.getStdOut().writer(), true);
    defer ctxt.deinit();

    std.debug.print("program result: {}\n", .{try Interpreter.run(&ctxt)});
}
