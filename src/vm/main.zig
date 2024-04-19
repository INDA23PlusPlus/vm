const std = @import("std");
const arch = @import("arch");
const Instruction = arch.Instruction;
const Program = arch.Program;
const interpreter = @import("interpreter.zig");
const VMContext = @import("VMContext.zig");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var output_stream = std.io.getStdOut();
    const output_writer = output_stream.writer();

    const prog = Program.init(&.{
        Instruction.pushs(0),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{"Hello World!"}, &.{});

    var ctxt = VMContext.init(prog, gpa.allocator(), &output_writer, false);
    defer ctxt.deinit();

    return @intCast(try interpreter.run(&ctxt));
}
