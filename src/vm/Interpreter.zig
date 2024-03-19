//!
//! Main interpreter
//!

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Type = @import("types.zig").Type;
const Instruction = @import("arch").instr.Instruction;
const VMInstruction = @import("VMInstruction.zig");

fn assert(b: bool) !void {
    if (!b and (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)) {
        return error.AssertionFailed;
    }
}

fn applyArithmetic(op: Instruction, comptime T: type, a: T, b: T) T {
    return switch (op) {
        .add => a + b,
        .sub => a - b,
        .mul => a * b,
        .div => std.debug.panic("not decided how to handle this yet", .{}),
        .mod => std.debug.panic("not decided how to handle this yet", .{}),
        else => unreachable,
    };
}

fn doArithmetic(a: Type, op: Instruction, b: Type) !Type {
    if (a.as(.int)) |ai| {
        if (b.as(.int)) |bi| {
            return Type.from(applyArithmetic(op, i64, ai, bi));
        }
    }

    if (a.as(.float)) |af| {
        if (b.as(.float)) |bf| {
            return Type.from(applyArithmetic(op, f64, af, bf));
        }
    }

    // TODO: should we cast ints to floats or vice versa?
    return error.NonMatchingTypes;
}

pub fn floatValue(x: anytype) f64 {
    return x.as(.float) orelse @floatFromInt(x.as(.int).?);
}

/// returns exit code of the program
pub fn run(code: []const VMInstruction, allocator: Allocator) !void {
    var ip: usize = 0;
    var stack = std.ArrayList(Type).init(allocator);

    while (ip < code.len) {
        const i = code[ip];
        switch (i.op) {
            .add, .sub, .mul, .div, .mod => |op| {
                try assert(stack.items.len >= 2);
                const a = &stack.items[stack.items.len - 1];
                const b = &stack.items[stack.items.len - 2];

                const res = try doArithmetic(b.*, op, a.*);
                std.debug.print("arithmetic: {d} {s} {d}\n", .{ floatValue(b), @tagName(op), floatValue(a) });
                b.* = res;
                _ = stack.pop();
            },
            .push => {
                const pushed_val = Type.from(i.operand);
                std.debug.print("pushed: {}\n", .{pushed_val});
                try stack.append(pushed_val);
            },
            .pop => {
                try assert(stack.items.len > 0);
                var popped_val = stack.popOrNull().?;
                defer popped_val.deinit();
                std.debug.print("popped: {}\n", .{popped_val});
            },
            else => std.debug.panic("unimplemented instruction {}\n", .{i}),
        }
        if (i.op != .jmp and i.op != .jmpnz) {
            ip += 1;
        }
    }
}
