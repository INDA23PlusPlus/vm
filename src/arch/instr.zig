const std = @import("std");

pub const Instruction = enum(u8) {
    // TODO: explicit opcodes

    add, // [a, b] -> [a + b]
    sub, // [a, b] -> [a - b]
    mul, // [a, b] -> [a * b]
    div, // [a, b] -> [a / b] (rounds toward zero)
    mod, // [a, b] -> [a % b] TODO: decide how to handle modulo/remainder

    // 1 if true, 0 if false
    cmp_lt, // [a, b] -> [a < b]
    cmp_gt, // [a, b] -> [a > b]
    cmp_le, // [a, b] -> [a <= b]
    cmp_ge, // [a, b] -> [a <= b]
    cmp_eq, // [a, b] -> [a == b]
    cmp_ne, // [a, b] -> [a != b]

    jmp,
    jmpnz, // [a] -> []

    push,
    pop,
    dup, // [a] -> [a, a]

    load, // OP i,  [] -> [value] where value = stack[OBP + i]
    store, // OP i,  [value] -> [] sets stack[OBP] = value

    call,
    ret,

    struct_alloc, // [] -> [s] where s is a reference to the newly allocated struct
    struct_drop, // [s] -> []
    struct_load, // [s, f] -> [s, v] where v = s.f
    struct_store, // [s, f] -> [r]

    list_alloc, // [] -> [l] where l is a reference to the newly allocated list
    list_drop,
    list_load, // [l, i] -> [l, v] where v = l[i]
    list_store, // [l, i, v] -> [l] sets l[i] = v

    /// Returns wether an operand is to be expected following this instruction
    pub fn hasOperand(self: Instruction) bool {
        const arr = comptime blk: {
            // add instructions with operands here
            const instrs = [_]Instruction{
                // zig fmt off
                .jmp,       .jmpnz,      .push,         .load,
                .store,     .call,       .ret,          .list_alloc,
                .list_load, .list_store, .struct_alloc, .struct_load,
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
