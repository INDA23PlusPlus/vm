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

fn doArithmetic(op: Instruction, comptime T: type, a: T, b: T) T {
    return switch (op) {
        .add => a + b,
        .sub => a - b,
        .mul => a * b,
        .div => if (a < 0 or b < 0) std.debug.panic("not decided how to handle division or modulo involving negative numbers yet", .{}) else @divFloor(a, b),
        .mod => if (a < 0 or b < 0) std.debug.panic("not decided how to handle division or modulo involving negative numbers yet", .{}) else @mod(a, b),
        else => unreachable,
    };
}

fn doComparison(op: Instruction, comptime T: type, a: T, b: T) i64 {
    return switch (op) {
        .cmp_lt => @intFromBool(a < b),
        .cmp_gt => @intFromBool(a > b),
        .cmp_le => @intFromBool(a <= b),
        .cmp_ge => @intFromBool(a >= b),
        .cmp_eq => @intFromBool(a == b),
        .cmp_ne => @intFromBool(a != b),
        else => unreachable,
    };
}

fn doBinaryOp(a: Type, op: Instruction, b: Type) !Type {
    if (a.as(.int)) |ai| {
        if (b.as(.int)) |bi| {
            if (op.isArithmetic()) {
                return Type.from(doArithmetic(op, i64, ai, bi));
            } else if (op.isComparison()) {
                return Type.from(doComparison(op, i64, ai, bi));
            } else {
                return error.InvalidOperation;
            }
        }
    }

    if (a.as(.float)) |af| {
        if (b.as(.float)) |bf| {
            if (op.isArithmetic()) {
                return Type.from(doArithmetic(op, f64, af, bf));
            } else if (op.isComparison()) {
                return Type.from(doComparison(op, f64, af, bf));
            } else {
                return error.InvalidOperation;
            }
        }
    }

    // TODO: should we cast ints to floats or vice versa?
    return error.NonMatchingTypes;
}

pub fn floatValue(x: anytype) f64 {
    return x.as(.float) orelse @floatFromInt(x.as(.int).?);
}

/// returns exit code of the program
pub fn run(code: []const VMInstruction, allocator: Allocator, debug_output: bool) !i64 {
    var ip: usize = 0;
    var stack = std.ArrayList(Type).init(allocator);
    defer stack.deinit();

    while (ip < code.len) {
        const i = code[ip];
        switch (i.op) {
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .cmp_lt,
            .cmp_gt,
            .cmp_le,
            .cmp_ge,
            .cmp_eq,
            .cmp_ne,
            => |op| {
                assert(stack.items.len >= 2) catch |e| {
                    std.debug.print("stack contents: {any}\n", .{stack.items});
                    return e;
                };
                const a = &stack.items[stack.items.len - 1];
                const b = &stack.items[stack.items.len - 2];

                const res = try doBinaryOp(b.*, op, a.*);
                if (debug_output) {
                    std.debug.print("arithmetic: {d} {s} {d} = {d}\n", .{ floatValue(b), @tagName(op), floatValue(a), floatValue(res) });
                }
                b.* = res;
                _ = stack.pop();
            },
            .dup => {
                try assert(stack.items.len >= 1);
                const dup_val = stack.items[stack.items.len - 1];
                if (debug_output) {
                    std.debug.print("duplicated: {}\n", .{dup_val});
                }
                try stack.append(dup_val);
            },
            .push => {
                const pushed_val = Type.from(i.operand);
                if (debug_output) {
                    std.debug.print("pushed: {}\n", .{pushed_val});
                }
                try stack.append(pushed_val);
            },
            .pop => {
                try assert(stack.items.len >= 1);
                var popped_val = stack.pop();
                defer popped_val.deinit();
                if (debug_output) {
                    std.debug.print("popped: {}\n", .{popped_val});
                }
            },
            .jmp => {
                const offset = i.operand;
                if (debug_output) {
                    std.debug.print("jumping: {}\n", .{offset});
                }

                if (offset < 0) {
                    const back_dist = std.math.absCast(offset);
                    try assert(ip >= back_dist);
                    ip -= @intCast(back_dist);
                } else {
                    ip += @intCast(offset);
                }
            },
            .jmpnz => {
                try assert(stack.items.len >= 1);

                var popped_val = stack.pop();
                try assert(popped_val.tag() == .int);
                if (popped_val.as(.int).? != 0) {
                    const offset = i.operand;
                    if (debug_output) {
                        std.debug.print("took branch: {}\n", .{offset});
                    }
                    if (offset < 0) {
                        const back_dist = std.math.absCast(offset);
                        try assert(ip >= back_dist); // cant jump before start of program
                        ip -= @intCast(back_dist);
                    } else {
                        ip += @intCast(offset);
                    }
                } else {
                    const offset = i.operand;
                    if (debug_output) {
                        std.debug.print("didn't take branch: {}\n", .{offset});
                    }
                    ip += 1;
                }
            },
            else => std.debug.panic("unimplemented instruction {}\n", .{i}),
        }
        if (i.op != .jmp) {
            ip += 1;
        }
    }
    if (stack.items.len == 0) {
        return error.NoReturnValue;
    } else {
        return stack.items[stack.items.len - 1].as(.int) orelse error.NonIntReturnValue;
    }
}

test "arithmetic" {
    const util = struct {
        fn testArithmetic(op: Instruction) !void {
            for (0..100) |a| {
                for (1..100) |b| {
                    const lhs: i64 = @intCast(a);
                    const rhs: i64 = @intCast(b);

                    const res: i64 = switch (op) {
                        .add => lhs + rhs,
                        .sub => lhs - rhs,
                        .mul => lhs * rhs,
                        .div => @intCast(a / b),
                        .mod => @intCast(a % b),
                        else => unreachable,
                    };

                    try std.testing.expectEqual(res, try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(rhs),
                            VMInstruction{ .op = op, .operand = -1 },
                        },
                        std.testing.allocator,
                        false,
                    ));
                }
            }
        }

        fn testComparisons() !void {
            for (0..100) |a| {
                for (a + 1..100) |b| {
                    const lhs: i64 = @intCast(a);
                    const rhs: i64 = @intCast(b);

                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.equal(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                    try std.testing.expectEqual(@as(i64, 0), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.notEqual(),
                        },
                        std.testing.allocator,
                        false,
                    ));

                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.greaterEqual(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.lessEqual(),
                        },
                        std.testing.allocator,
                        false,
                    ));

                    try std.testing.expectEqual(@as(i64, 0), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.notEqual(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(lhs),
                            VMInstruction.equal(),
                        },
                        std.testing.allocator,
                        false,
                    ));

                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(rhs),
                            VMInstruction.less(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                    try std.testing.expectEqual(@as(i64, 0), try run(
                        &.{
                            VMInstruction.push(rhs),
                            VMInstruction.push(lhs),
                            VMInstruction.less(),
                        },
                        std.testing.allocator,
                        false,
                    ));

                    try std.testing.expectEqual(@as(i64, 0), try run(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(rhs),
                            VMInstruction.greater(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                    try std.testing.expectEqual(@as(i64, 1), try run(
                        &.{
                            VMInstruction.push(rhs),
                            VMInstruction.push(lhs),
                            VMInstruction.greater(),
                        },
                        std.testing.allocator,
                        false,
                    ));
                }
            }
        }
    };

    try util.testArithmetic(.add);
    try util.testArithmetic(.sub);
    try util.testArithmetic(.mul);
    try util.testArithmetic(.div);
    try util.testArithmetic(.mod);

    try util.testComparisons();

    try std.testing.expectEqual(@as(i64, 0), try run(
        &.{
            VMInstruction.push(0),
            VMInstruction.dup(),
            VMInstruction.pop(),
        },
        std.testing.allocator,
        false,
    ));

    // decrement value, starting at 10, until its zero, 10 is not special, any value should work
    try std.testing.expectEqual(@as(i64, 0), try run(
        &.{
            VMInstruction.push(10),
            VMInstruction.push(1),
            VMInstruction.sub(),
            VMInstruction.dup(),
            VMInstruction.jmpnz(-4), // jump to push 1
        },
        std.testing.allocator,
        false,
    ));
}
