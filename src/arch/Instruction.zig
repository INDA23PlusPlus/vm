//!
//! Instruction representation
//!

const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;

const Self = @This();

op: Opcode,
operand: packed union {
    int: i64,
    float: f64,
    location: usize,
    field_id: usize,
    none: void,
} = .{ .none = void{} }, // either an immediate i64 value or a number of instructions to jump forward or backward

pub fn push(value: i64) Self {
    return .{ .op = .push, .operand = .{ .int = value } };
}

pub fn pushf(value: f64) Self {
    return .{ .op = .pushf, .operand = .{ .float = value } };
}

pub fn pushs(value: usize) Self {
    return .{ .op = .pushs, .operand = .{ .location = value } };
}

pub fn pop() Self {
    return .{ .op = .pop };
}

pub fn dup() Self {
    return .{ .op = .dup };
}

pub fn load(pos: i64) Self {
    return .{ .op = .load, .operand = .{ .int = pos } };
}

pub fn syscall(num: i64) Self {
    return .{ .op = .syscall, .operand = .{ .int = num } };
}

pub fn call(destination: usize) Self {
    return .{ .op = .call, .operand = .{ .location = destination } };
}

pub fn ret() Self {
    return .{ .op = .ret };
}

pub fn store(pos: i64) Self {
    return .{ .op = .store, .operand = .{ .int = pos } };
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
pub fn increment() Self {
    return .{ .op = .inc };
}
pub fn sub() Self {
    return .{ .op = .sub };
}
pub fn decrement() Self {
    return .{ .op = .dec };
}
pub fn negate() Self {
    return .{ .op = .neg };
}
pub fn mul() Self {
    return .{ .op = .mul };
}
pub fn div() Self {
    return .{ .op = .div };
}
pub fn mod() Self {
    return .{ .op = .mod };
}

pub fn logicalOr() Self {
    return .{ .op = .log_or };
}
pub fn logicalAnd() Self {
    return .{ .op = .log_and };
}
pub fn logicalNot() Self {
    return .{ .op = .log_not };
}

pub fn bitwiseOr() Self {
    return .{ .op = .bit_or };
}
pub fn bitwiseXor() Self {
    return .{ .op = .bit_xor };
}
pub fn bitwiseAnd() Self {
    return .{ .op = .bit_and };
}
pub fn bitwiseNot() Self {
    return .{ .op = .bit_not };
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

pub fn structAlloc() Self {
    return .{ .op = .struct_alloc };
}
pub fn structLoad(field: usize) Self {
    return .{ .op = .struct_load, .operand = .{ .field_id = field } };
}
pub fn structStore(field: usize) Self {
    return .{ .op = .struct_store, .operand = .{ .field_id = field } };
}

pub fn listAlloc() Self {
    return .{ .op = .list_alloc };
}
pub fn listLoad() Self {
    return .{ .op = .list_load };
}
pub fn listStore() Self {
    return .{ .op = .list_store };
}
pub fn listLength() Self {
    return .{ .op = .list_length };
}
pub fn listAppend() Self {
    return .{ .op = .list_append };
}
pub fn listPop() Self {
    return .{ .op = .list_pop };
}
pub fn listRemove() Self {
    return .{ .op = .list_remove };
}
pub fn listConcat() Self {
    return .{ .op = .list_concat };
}
