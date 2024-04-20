const std = @import("std");

pub const Opcode = enum(u8) {
    // TODO: explicit opcodes (actually a unified instruction interface towards assembler/vm makes this unecessary)

    // see descr.zig for descriptions
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
    pushf,
    pushs,
    pop,
    dup,

    load,
    store,

    syscall, //TODO: keep or remove syscalls as a concept
    call,
    ret,

    stack_alloc,

    struct_alloc,
    struct_load,
    struct_store,

    list_alloc,
    list_load,
    list_store,

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
                .jmp,         .jmpnz,        .push,        .pushf,     .pushs,      .load,
                .store,       .call,         .list_alloc,  .list_load, .list_store, .struct_alloc,
                .struct_load, .struct_store, .stack_alloc,
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
