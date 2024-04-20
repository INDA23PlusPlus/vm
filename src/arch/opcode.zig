const std = @import("std");

pub const Opcode = enum(u8) {
    // TODO: explicit opcodes (actually a unified instruction interface towards assembler/vm makes this unecessary)

    // WARNING: Please change corresponding entries in descr.zig and hasOperand if you
    // add or change anything here.

    // TODO: define overflow behavior for integers
    // Implemented with two's complement wrapping for now
    add, // [a, b] -> [a + b]
    sub, // [a, b] -> [a - b]
    mul, // [a, b] -> [a * b]
    div, // [a, b] -> [a / b] (rounds toward zero)
    mod, // [a, b] -> [a % b] TODO: decide how to handle modulo/remainder
    // Implemented such that { a mod b = a - b(a / b) } for now

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
    pushf, // OP @value [] -> [value]
    pushs, // OP %value [] -> [string @ value]
    pop, // [a] -> []
    dup, // [a] -> [a, a]

    load, // OP %i [] -> [value] where value = stack[BP + i]
    store, // OP %i [value] -> [] sets stack[BP + i] = value

    syscall, // [args...] -> [ret...] TODO: keep or remove syscalls as a concept
    // 0: write value to output ([value] -> [])
    call, // OP .f [param 0, ..., param N - 1, N] -> [param 0, ..., param N - 1, N, BP, return_address]
    // see accompanying `README.md`
    ret, // [param 0, ..., param N - 1, N, BP, ..., return_address, return_value] -> [return_value]
    // see accompanying `README.md`

    stack_alloc, // Allocates N unit object on the stack

    struct_alloc, // [] -> [s] where s is a reference to the newly allocated struct
    struct_load, // [s, f] -> [s, v] where v = s.f
    struct_store, // [s, f] -> [r]

    list_alloc, // [] -> [l] where l is a reference to the newly allocated list
    list_load, // [l, i] -> [l, v] where v = l[i]
    list_store, // [l, i, v] -> [l] sets l[i] = v

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

    /// Returns whether an operand is to be expected following this instruction
    pub fn hasOperand(self: Opcode) bool {
        const arr = comptime blk: {
            // add instructions with operands here
            const instrs = [_]Opcode{
                // zig fmt off
                .jmp,          .jmpnz,       .push,         .pushf,       .load,
                .store,        .call,        .list_alloc,   .list_load,   .list_store,
                .struct_alloc, .struct_load, .struct_store, .stack_alloc,
                .syscall,
                // zig fmt on
            };
            var arr = std.EnumArray(Opcode, bool).initFill(false);
            for (instrs) |i| arr.set(i, true);
            break :blk arr;
        };
        return arr.get(self);
    }
};
