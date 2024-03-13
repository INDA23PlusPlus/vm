const std = @import("std");

pub const Instruction = enum(u8) {
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
};

pub const prefix = struct {
    pub const keyword = '-';
    pub const label = '.';
    pub const literal = '%';
};
