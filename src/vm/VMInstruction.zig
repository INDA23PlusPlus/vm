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

pub fn dup() Self {
    return .{ .op = .dup, .operand = -1 };
}

pub fn jmp(offset: i64) Self {
    return .{ .op = .jmp, .operand = offset };
}

pub fn jmpnz(offset: i64) Self {
    return .{ .op = .jmpnz, .operand = offset };
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

pub fn less() Self {
    return .{ .op = .cmp_lt, .operand = -1 };
}

pub fn lessEqual() Self {
    return .{ .op = .cmp_le, .operand = -1 };
}

pub fn greater() Self {
    return .{ .op = .cmp_gt, .operand = -1 };
}

pub fn greaterEqual() Self {
    return .{ .op = .cmp_ge, .operand = -1 };
}

pub fn equal() Self {
    return .{ .op = .cmp_eq, .operand = -1 };
}

pub fn notEqual() Self {
    return .{ .op = .cmp_ne, .operand = -1 };
}
