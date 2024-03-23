const std = @import("std");

pub const Instruction = enum(u8) {
    // TODO: explicit opcodes

    add, // [a, b] -> [a + b]
    sub, // [a, b] -> [a - b]
    mul, // [a, b] -> [a * b]
    div, // [a, b] -> [a / b] (rounds toward zero)
    mod, // [a, b] -> [a % b] TODO: decide how to handle modulo/remainder

    // 1 if true, 0 if false
    cmp_lt, // [a, b] -> [res] where res = a < b
    cmp_gt, // [a, b] -> [res] where res = a > b
    cmp_le, // [a, b] -> [res] where res = a <= b
    cmp_ge, // [a, b] -> [res] where res = a <= b
    cmp_eq, // [a, b] -> [res] where res = a == b
    cmp_ne, // [a, b] -> [res] where res = a != b

    jmp, // OP .destination [] -> [] control flow continues at .destination
    jmpnz, // OP .destination [a] -> [] control flow continues at .destination if a != 0

    push, // OP %value [] -> [value]
    pop, // [a] -> []
    dup, // [a] -> [a, a]

    load, // OP %i [] -> [value] where value = stack[OBP + i]
    store, // OP %i [value] -> [] sets stack[OBP + i] = value

    call, // [param 0, ..., param N - 1,  f] -> [param 0, ..., param N - 1, ret, OBP, N, local 0, ... local M - 1, M]
    // execution continues at function f
    // ret is return address
    // params indexed by PARAM_ID + OBP - (M + N + 3)
    // locals indexed by LOCAL_ID + OBP - (M + 1)
    // TODO: complete this
    ret, // [param 1, ..., param N, ret, OBP, N, local 1, ... local M, M] -> []
    // execution continues at ret

    stack_allock, // Allocates N uninitialized object on the stack

    struct_alloc, // [] -> [s] where s is a reference to the newly allocated struct
    struct_drop, // [s] -> [] tells memory manager this struct isnt being referred to from this scope anymore TODO: these should be implicit
    struct_load, // [s, f] -> [s, v] where v = s.f
    struct_store, // [s, f] -> [r]

    list_alloc, // [] -> [l] where l is a reference to the newly allocated list
    list_drop, // [l] -> [] tells memory manager this list isnt being referred to from this scope anymore TODO: see struct_drop above
    list_load, // [l, i] -> [l, v] where v = l[i]
    list_store, // [l, i, v] -> [l] sets l[i] = v

    pub fn isArithmetic(self: Instruction) bool {
        return switch (self) {
            .add => true,
            .sub => true,
            .mul => true,
            .div => true,
            .mod => true,
            else => false,
        };
    }

    pub fn isComparison(self: Instruction) bool {
        return switch (self) {
            .cmp_lt => true,
            .cmp_gt => true,
            .cmp_le => true,
            .cmp_ge => true,
            .cmp_eq => true,
            .cmp_ne => true,
            else => false,
        };
    }

    /// Returns whether an operand is to be expected following this instruction
    pub fn hasOperand(self: Instruction) bool {
        const arr = comptime blk: {
            // add instructions with operands here
            const instrs = [_]Instruction{
                // zig fmt off
                .jmp,        .jmpnz,        .push,        .load,
                .store,      .call,         .list_alloc,  .list_load,
                .list_store, .struct_alloc, .struct_load,
                .struct_store,
                // zig fmt on
            };
            var arr = std.EnumArray(Instruction, bool).initFill(false);
            for (instrs) |i| arr.set(i, true);
            break :blk arr;
        };
        return arr.get(self);
    }
};

/// The prefix for tokens in the IR
/// E.g. `-function` or `.label`
pub const prefix = struct {
    pub const keyword = '-';
    pub const label = '.';
    pub const literal = '%';
};

pub const entry_name = "main";
