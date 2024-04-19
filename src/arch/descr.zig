//!
//! Textual descriptions of instructions.
//!

const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;

pub const text = blk: {
    var arr = std.EnumArray(Opcode, []const u8).initUndefined();
    arr.set(.add, " [a, b] -> [a + b]");
    arr.set(.sub, " [a, b] -> [a - b]");
    arr.set(.mul, " [a, b] -> [a * b]");
    arr.set(.div, " [a, b] -> [a / b] (rounds toward zero)");
    arr.set(.mod, " [a, b] -> [a % b] TODO: decide how to handle modulo/remainder");
    arr.set(.cmp_lt, " [a, b] -> [res] where res = a < b");
    arr.set(.cmp_gt, " [a, b] -> [res] where res = a > b");
    arr.set(.cmp_le, " [a, b] -> [res] where res = a <= b");
    arr.set(.cmp_ge, " [a, b] -> [res] where res = a <= b");
    arr.set(.cmp_eq, " [a, b] -> [res] where res = a == b");
    arr.set(.cmp_ne, " [a, b] -> [res] where res = a != b");
    arr.set(.jmp, " OP .destination [] -> [] control flow continues at .destination");
    arr.set(.jmpnz, " OP .destination [a] -> [] control flow continues at .destination if a != 0");
    arr.set(.push, " OP %value [] -> [value]");
    arr.set(.pushf, " OP @value [] -> [value]");
    arr.set(.pop, " [a] -> []");
    arr.set(.dup, " [a] -> [a, a]");
    arr.set(.load, " OP %i [] -> [value] where value = stack[BP + i]");
    arr.set(.store, " OP %i [value] -> [] sets stack[BP + i] = value");
    arr.set(.syscall, " [args...] -> [ret...] TODO: keep or remove");
    arr.set(.call, " OP .f [param 0, ..., param N - 1, N] -> [param 0, ..., param N - 1, N, BP, return_address]");
    arr.set(.ret, " [param 0, ..., param N - 1, N, BP, ..., return_address, return_value] -> [return_value]");
    arr.set(.stack_alloc, " Allocates N unit object on the stack");
    arr.set(.struct_alloc, " [] -> [s] where s is a reference to the newly allocated struct");
    arr.set(.struct_load, " [s, f] -> [s, v] where v = s.f");
    arr.set(.struct_store, " [s, f] -> [r]");
    arr.set(.list_alloc, " [] -> [l] where l is a reference to the newly allocated list");
    arr.set(.list_load, " [l, i] -> [l, v] where v = l[i]");
    arr.set(.list_store, " [l, i, v] -> [l] sets l[i] = v");
    break :blk arr;
};
