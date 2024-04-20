//!
//! Textual descriptions of instructions.
//!

const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;

pub const text = blk: {
    var arr = std.EnumArray(Opcode, []const u8).initUndefined();
    const Entry = struct { Opcode, []const u8 };
    const entries = [_]Entry{
        .{ .add, " [a, b] -> [a + b]" },
        .{ .sub, " [a, b] -> [a - b]" },
        .{ .mul, " [a, b] -> [a * b]" },
        .{ .div, " [a, b] -> [a / b] (rounds toward zero)" },
        .{ .mod, " [a, b] -> [a % b] TODO: decide how to handle modulo/remainder" },
        .{ .cmp_lt, " [a, b] -> [res] where res = a < b" },
        .{ .cmp_gt, " [a, b] -> [res] where res = a > b" },
        .{ .cmp_le, " [a, b] -> [res] where res = a <= b" },
        .{ .cmp_ge, " [a, b] -> [res] where res = a <= b" },
        .{ .cmp_eq, " [a, b] -> [res] where res = a == b" },
        .{ .cmp_ne, " [a, b] -> [res] where res = a != b" },
        .{ .jmp, " OP .destination [] -> [] control flow continues at .destination" },
        .{ .jmpnz, " OP .destination [a] -> [] control flow continues at .destination if a != 0" },
        .{ .push, " OP %value [] -> [value]" },
        .{ .pushf, " OP @value [] -> [value]" },
        .{ .pop, " [a] -> []" },
        .{ .dup, " [a] -> [a, a]" },
        .{ .load, " OP %i [] -> [value] where value = stack[BP + i]" },
        .{ .store, " OP %i [value] -> [] sets stack[BP + i] = value" },
        .{ .syscall, " [args...] -> [ret...] TODO: keep or remove" },
        .{ .call, " OP .f [param 0, ..., param N - 1, N] -> [param 0, ..., param N - 1, N, BP, return_address]" },
        .{ .ret, " [param 0, ..., param N - 1, N, BP, ..., return_address, return_value] -> [return_value]" },
        .{ .stack_alloc, " Allocates N unit object on the stack" },
        .{ .struct_alloc, "[] -> [s] where s is a reference to the newly allocated struct" },
        .{ .struct_load, "OP %f [s] -> [v] where v = s.f" },
        .{ .struct_store, "OP %f [s, v] -> [] sets s.f = v" },
        .{ .list_alloc, " [] -> [l] where l is a reference to the newly allocated list" },
        .{ .list_load, " [l, i] -> [l, v] where v = l[i]" },
        .{ .list_store, " [l, i, v] -> [l] sets l[i] = v" },
    };

    for (entries) |entry| arr.set(entry.@"0", entry.@"1");
    break :blk arr;
};
