//!
//! VM internal instruction representation
//!

const std = @import("std");
const Instruction = @import("arch").instr.Instruction;

const Self = @This();

op: Instruction,
operand: i64, // either an immediate i64 value or a number of instructions to jump forward or backward

pub fn push(value: i64) Self {
    return .{ .op = .push, .operand = value };
}

pub fn pop() Self {
    return .{ .op = .pop, .operand = -1 };
}
