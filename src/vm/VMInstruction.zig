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

pub fn add() Self {
    return .{ .op = .add, .operand = -1 };
}

pub fn sub() Self {
    return .{ .op = .sub, .operand = -1 };
}

pub fn mul() Self {
    return .{ .op = .sub, .operand = -1 };
}

pub fn div() Self {
    return .{ .op = .div, .operand = -1 };
}

pub fn mod() Self {
    return .{ .op = .mod, .operand = -1 };
}
