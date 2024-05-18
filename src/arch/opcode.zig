const std = @import("std");

pub const Opcode = enum(u8) {
    // TODO: explicit opcodes (actually a unified instruction interface towards assembler/vm makes this unecessary)

    // see descr.zig for descriptions
    add = 0,
    sub = 1,
    mul = 2,
    neg = 3,
    div = 4,
    mod = 5,
    inc = 6,
    dec = 7,
    log_or = 8,
    // no logical xor, use cmp_ne
    log_and = 9,
    log_not = 10,
    bit_or = 11,
    bit_xor = 12,
    bit_and = 13,
    bit_not = 14,
    cmp_lt = 15,
    cmp_gt = 16,
    cmp_le = 17,
    cmp_ge = 18,
    cmp_eq = 19,
    cmp_ne = 20,

    jmp = 21,
    jmpnz,

    push,
    pushf,
    pushs,
    pop,
    dup,

    load,
    store,

    syscall, //TODO: keep or remove syscalls as a concept

    call, // not said to have one specific arity because it can have any arity
    ret,

    stack_alloc,

    struct_alloc,
    struct_load,
    struct_store,

    list_alloc,
    list_load,
    list_store,

    list_length,
    list_append,
    list_pop,
    list_remove,
    list_concat,

    pub fn arity(self: Opcode) ?usize {
        if (self.isNullary()) return 0;
        if (self.isUnary()) return 1;
        if (self.isBinary()) return 2;
        if (self.isTernary()) return 3;
        return null;
    }

    pub fn isNullary(self: Opcode) bool {
        return switch (self) {
            .push,
            .pushf,
            .pushs,
            .struct_alloc,
            .list_alloc,
            .jmp,
            .load,
            .pop,
            => true,
            else => false,
        };
    }

    pub fn isUnary(self: Opcode) bool {
        return switch (self) {
            .neg,
            .inc,
            .dec,
            .bit_not,
            .log_not,
            .list_length,
            .list_pop,
            .ret,
            .jmpnz,
            => true,
            else => false,
        };
    }

    pub fn isBinary(self: Opcode) bool {
        return switch (self) {
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .log_or,
            .log_and,
            .cmp_lt,
            .cmp_gt,
            .cmp_le,
            .cmp_ge,
            .cmp_eq,
            .cmp_ne,
            .list_append,
            .list_concat,
            .list_load,
            .list_remove,
            => true,
            else => false,
        };
    }

    pub fn isTernary(self: Opcode) bool {
        return switch (self) {
            .list_store,
            => true,
            else => false,
        };
    }

    pub fn isArithmetic(self: Opcode) bool {
        return switch (self) {
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            => true,
            else => false,
        };
    }

    pub fn isComparison(self: Opcode) bool {
        return switch (self) {
            .cmp_lt,
            .cmp_gt,
            .cmp_le,
            .cmp_ge,
            .cmp_eq,
            .cmp_ne,
            => true,
            else => false,
        };
    }

    pub fn isLogical(self: Opcode) bool {
        return switch (self) {
            .log_and,
            .log_or,
            .log_not,
            => true,
            else => false,
        };
    }

    pub fn isBitwise(self: Opcode) bool {
        return switch (self) {
            .bit_and,
            .bit_or,
            .bit_xor,
            .bit_not,
            => true,
            else => false,
        };
    }

    /// Returns whether an operand is to be expected following this instruction
    pub fn hasOperand(self: Opcode) bool {
        return switch (self) {
            .jmp,
            .jmpnz,
            .push,
            .pushf,
            .pushs,
            .load,
            .store,
            .call,
            .struct_load,
            .struct_store,
            .stack_alloc,
            .syscall,
            => true,
            else => false,
        };
    }
};
