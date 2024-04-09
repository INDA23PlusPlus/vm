const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMContext = @import("VMContext.zig");
const VMInstruction = @import("VMInstruction.zig");
const VMProgram = @import("VMProgram.zig");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const prog = VMProgram.init(&.{
        VMInstruction.pushs(0),
        VMInstruction.syscall(0),
        VMInstruction.push(0),
        VMInstruction.ret(),
    }, 0, &.{"Hello World!"});

    var ctxt = VMContext.init(prog, gpa.allocator(), std.io.getStdOut().writer(), false);
    defer ctxt.deinit();

    return @intCast(try Interpreter.run(&ctxt));
}
