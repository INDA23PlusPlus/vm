const std = @import("std");

pub const Instruction = enum(u8) {
    // TODO: explicit opcodes
    add,
    sub,
    mul,
    div,
    mod,
    cmp_lt,
    cmp_gt,
    cmp_le,
    cmp_ge,
    cmp_eq,
    cmp_ne,
    jmp,
    jmpnz,
    push,
    pop,
    load,
    store,
    call,
    ret,
    struct_alloc,
    struct_load,
    struct_store,
    list_alloc,
    list_drop,
    list_load,
    list_store,

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
