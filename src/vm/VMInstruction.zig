//!
//! VM internal instruction representation
//!

const std = @import("std");
const Instruction = @import("arch").instr.Instruction;
const UnitType = @import("types.zig").UnitType;

const Self = @This();

op: Instruction,
operand: union {
    int: i64,
    float: f64,
    location: usize,
    none: UnitType,
} = .{ .none = .{} }, // either an immediate i64 value or a number of instructions to jump forward or backward

pub fn push(value: i64) Self {
    return .{ .op = .push, .operand = .{ .int = value } };
}

pub fn pop() Self {
    return .{ .op = .pop };
}

pub fn dup() Self {
    return .{ .op = .dup };
}

pub fn jmp(destination: usize) Self {
    return .{ .op = .jmp, .operand = .{ .location = destination } };
}

pub fn jmpnz(destination: usize) Self {
    return .{ .op = .jmpnz, .operand = .{ .location = destination } };
}

pub fn add() Self {
    return .{ .op = .add };
}

pub fn sub() Self {
    return .{ .op = .sub };
}

pub fn mul() Self {
    return .{ .op = .sub };
}

pub fn div() Self {
    return .{ .op = .div };
}

pub fn mod() Self {
    return .{ .op = .mod };
}

pub fn less() Self {
    return .{ .op = .cmp_lt };
}

pub fn lessEqual() Self {
    return .{ .op = .cmp_le };
}

pub fn greater() Self {
    return .{ .op = .cmp_gt };
}

pub fn greaterEqual() Self {
    return .{ .op = .cmp_ge };
}

pub fn equal() Self {
    return .{ .op = .cmp_eq };
}

pub fn notEqual() Self {
    return .{ .op = .cmp_ne };
}
