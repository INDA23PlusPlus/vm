const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const VMContext = @import("VMContext.zig");
const Arch = @import("arch");
const Instruction = Arch.Instruction;
const Program = Arch.Program;

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

    return @intCast(try Interpreter.run(&ctxt));
}
