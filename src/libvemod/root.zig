const std = @import("std");

pub const ValueTag = enum(u8) {
    int,
    float,
    list,
    @"struct",
};

pub const Value = extern struct {
    tag: u8,
    data: extern union {
        int: i64,
        float: f64,
        ref: u64,
    },
};

pub const value_qbe_decl = "type :__vemod_value = { b, { { l } { d } { l } } }";

pub const Op = enum(u8) {
    /// Arithmetic
    add,
    sub,
    mul,
    div,
    mod,
    neg,

    /// Lists
    append,
    concat,
    index,
    length,

    /// Structs
    access,
    insert,

    /// Logic
    land,
    lor,
    lneg,

    // I/O
    print,
    println,
};

export fn __vemod_init() void {}

export fn __vemod_fini() void {}

export fn __vemod_print(v: i64) i64 {
    std.io.getStdOut().writer().print("{d}", .{v}) catch {};
    return 0;
}

export fn __vemod_println(v: i64) i64 {
    std.io.getStdOut().writer().print("{d}\n", .{v}) catch {};
    return 0;
}

// export fn __vemod_op1(op: Op, arg: Value) Value {}

// export fn __vemod_op2(op: Op, arg1: Value, arg2: Value) Value {}
