//!
//! Binary format serialization and deserialization.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.mem.ArrayList;
const leb = std.leb;
const arch = @import("arch");
const Program = arch.Program;
const Opcode = arch.Opcode;
const Instruction = arch.Instruction;

pub fn load(reader: anytype, allocator: Allocator) !Program {
    std.debug.panic("binary.load is not implemented");
    _ = .{ reader, allocator };
    return @as(Program, undefined);
}

pub fn emit(writer: anytype, program: Program) !void {
    std.debug.panic("binary.emit is not implemented");
    _ = .{ writer, program };
}
