//!
//! Main interpreter
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const Type = types.Type;
const Stack = std.ArrayList(Type);
const Instruction = @import("arch").instr.Instruction;
const VMInstruction = @import("VMInstruction.zig");
const VMProgram = @import("VMProgram.zig");

fn assert(b: bool) !void {
    if (!b and std.debug.runtime_safety) {
        return error.AssertionFailed;
    }
}

fn doArithmetic(comptime T: type, a: T, op: Instruction, b: T) T {
    return switch (op) {
        .add => a + b,
        .sub => a - b,
        .mul => a * b,
        .div => if (a < 0 or b < 0) std.debug.panic("not decided how to handle division or modulo involving negative numbers yet", .{}) else @divFloor(a, b),
        .mod => if (a < 0 or b < 0) std.debug.panic("not decided how to handle division or modulo involving negative numbers yet", .{}) else @mod(a, b),
        else => unreachable,
    };
}

fn doComparison(comptime T: type, a: T, op: Instruction, b: T) i64 {
    return @intFromBool(switch (op) {
        .cmp_lt => a < b,
        .cmp_gt => a > b,
        .cmp_le => a <= b,
        .cmp_ge => a >= b,
        .cmp_eq => a == b,
        .cmp_ne => a != b,
        else => unreachable,
    });
}

fn compareEq(a: Type, b: Type) bool {
    if (a.tag() != b.tag()) {
        const af = floatValue(a) catch return false;
        const bf = floatValue(b) catch return false;
        return af == bf;
    }

    return switch (a.tag()) {
        .unit => true,

        .int => a.as(.int).? == b.as(.int).?,
        .float => a.as(.float).? == b.as(.float).?,

        .list,
        .object,
        => std.debug.panic("TODO", .{}),
    };
}

fn doBinaryOp(a: Type, op: Instruction, b: Type) !Type {
    if (a.as(.int)) |ai| {
        if (b.as(.int)) |bi| {
            if (op.isArithmetic()) {
                return Type.from(doArithmetic(Type.GetRepr(.int), ai, op, bi));
            } else if (op.isComparison()) {
                return Type.from(doComparison(Type.GetRepr(.int), ai, op, bi));
            } else {
                return error.InvalidOperation;
            }
        }
    }

    if (op.isArithmetic()) {
        return Type.from(doArithmetic(Type.GetRepr(.float), try floatValue(a), op, try floatValue(b)));
    } else if (op.isComparison()) {
        return Type.from(doComparison(Type.GetRepr(.float), try floatValue(a), op, try floatValue(b)));
    } else {
        return error.InvalidOperation;
    }
}

var refc: i64 = 0;

fn take(v: Type) Type {
    if (std.debug.runtime_safety) {
        refc = refc + 1;
    }

    return v.clone();
}

fn drop(t: Type) void {
    if (std.debug.runtime_safety) {
        refc = refc - 1;
    }
    t.deinit();
}

fn get(stack: *Stack, obp: ?usize, pos: i64) !Type {
    const bp = obp orelse stack.items.len;
    const i: usize = switch (pos < 0) {
        true => bp - @as(usize, @intCast(-pos)),
        false => bp + @as(usize, @intCast(pos)),
    };

    assert(i < stack.items.len) catch |e| {
        std.debug.print("stack contents: {any}\n", .{stack.items});
        return e;
    };

    return take(stack.items[i]);
}

fn set(stack: *Stack, obp: ?usize, pos: i64, v: Type) !void {
    const bp = obp orelse stack.items.len;
    const i: usize = switch (pos < 0) {
        true => bp - @as(usize, @intCast(-pos)),
        false => bp + @as(usize, @intCast(pos)),
    };

    assert(i < stack.items.len) catch |e| {
        std.debug.print("stack contents: {any}\n", .{stack.items});
        return e;
    };

    drop(stack.items[i]);

    stack.items[i] = take(v);
}

fn push(stack: *Stack, v: Type) !void {
    try stack.append(take(v));
}

fn pop(stack: *Stack) !Type {
    assert(stack.items.len != 0) catch |e| {
        std.debug.print("stack contents: {any}\n", .{stack.items});
        return e;
    };

    return stack.pop();
}

fn instructionToString(op: Instruction) []const u8 {
    return switch (op) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .cmp_lt => "<",
        .cmp_gt => ">",
        .cmp_le => "<=",
        .cmp_ge => ">=",
        .cmp_eq => "==",
        .cmp_ne => "!= ",
        else => @tagName(op),
    };
}

fn floatValue(x: anytype) !f64 {
    if (x.as(.float)) |f|
        return f;
    if (x.as(.int)) |i|
        return @floatFromInt(i);

    return error.InvalidOperation;
}

/// returns exit code of the program
pub fn run(prog: *const VMProgram, allocator: Allocator, writer: anytype, debug_output: bool) !i64 {
    var ip: usize = prog.entry;
    var bp: usize = 0;
    var stack = Stack.init(allocator);
    defer stack.deinit();

    refc = 0;

    while (ip < prog.code.len) {
        const i = prog.code[ip];
        ip += 1;

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
            => |op| {
                var b = try pop(&stack);
                defer drop(b);
                var a = try pop(&stack);
                defer drop(a);

                const r = take(try doBinaryOp(a, op, b));
                defer drop(r);

                if (debug_output) {
                    if (op.isArithmetic()) {
                        std.debug.print("arithmetic: {} {s} {} = {}\n", .{ a, instructionToString(op), b, r });
                    }
                    if (op.isComparison()) {
                        std.debug.print("comparison: {} {s} {} = {}\n", .{ a, instructionToString(op), b, r });
                    }
                }

                try push(&stack, r);
            },
            // these have to be handled separately because they are valid for all types
            .cmp_eq,
            .cmp_ne,
            => |op| {
                var b = try pop(&stack);
                defer drop(b);
                var a = try pop(&stack);
                defer drop(a);

                const r = take(Type.from(@intFromBool(switch (op) {
                    .cmp_eq => compareEq(a, b),
                    .cmp_ne => !compareEq(a, b),
                    else => unreachable,
                })));
                defer drop(r);

                try push(&stack, r);
            },
            .push => {
                const v = take(Type.from(i.operand.int));
                defer drop(v);

                try push(&stack, v);
            },
            .pop => {
                drop(try pop(&stack));
            },
            .dup => {
                const v = try get(&stack, null, -1);
                defer drop(v);

                if (debug_output) {
                    std.debug.print("duplicated: {}\n", .{v});
                }

                try push(&stack, v);
            },
            .load => {
                const v = try get(&stack, bp, i.operand.int);
                defer drop(v);

                try push(&stack, v);
            },
            .store => {
                const v = try pop(&stack);
                defer drop(v);

                try set(&stack, bp, i.operand.int, v);
            },
            .syscall => {
                switch (i.operand.int) {
                    0 => {
                        const v = try pop(&stack);
                        defer drop(v);

                        try writer.print("{}\n", .{v});
                    },
                    else => {},
                }
            },
            .jmp => {
                const loc = i.operand.location;

                if (debug_output) {
                    std.debug.print("jumping to: {}\n", .{loc});
                }

                ip = loc;
            },
            .jmpnz => {
                const loc = i.operand.location;
                const v = try pop(&stack);
                defer drop(v);

                try assert(v.tag() == .int);

                if (v.int != 0) {
                    if (debug_output) {
                        std.debug.print("took branch to: {}\n", .{loc});
                    }

                    ip = loc;
                } else {
                    if (debug_output) {
                        std.debug.print("didn't take branch to: {}\n", .{loc});
                    }
                }
            },
            else => std.debug.panic("unimplemented instruction {}\n", .{i}),
        }
    }

    var r: Type.GetRepr(.int) = 0;
    {
        const rv = try pop(&stack);
        defer drop(rv);

        r = rv.as(.int) orelse return error.NonIntReturnValue;
    }

    assert(refc == stack.items.len) catch |e| {
        std.debug.print("refc = {}\n", .{refc});
        return e;
    };

    return r;
}

fn replaceWhiteSpace(buf: []const u8, allocator: Allocator) ![]const u8 {
    var res = std.ArrayList([]const u8).init(allocator);
    defer res.deinit();

    var iter = std.mem.tokenizeAny(u8, buf, " \n\r\t");
    while (iter.next()) |b| {
        try res.append(b);
    }

    return std.mem.join(allocator, " ", res.items);
}

fn testRun(code: []const VMInstruction, expected_output: []const u8, expected_exit_code: i64) !void {
    const output_buffer = try std.testing.allocator.alloc(u8, expected_output.len * 2);
    defer std.testing.allocator.free(output_buffer);

    var buf_writer = std.io.fixedBufferStream(output_buffer);

    try std.testing.expectEqual(expected_exit_code, try run(
        &VMProgram.init(code, 0),
        std.testing.allocator,
        buf_writer.writer(),
        false,
    ));

    const a = try replaceWhiteSpace(expected_output, std.testing.allocator);
    defer std.testing.allocator.free(a);
    const b = try replaceWhiteSpace(buf_writer.getWritten(), std.testing.allocator);
    defer std.testing.allocator.free(b);
    try std.testing.expect(std.mem.eql(u8, a, b));
}

test "arithmetic" {
    const util = struct {
        fn testBinaryOp(op: Instruction) !void {
            for (0..100) |a| {
                for (1..100) |b| {
                    const lhs: i64 = @intCast(a);
                    const rhs: i64 = @intCast(b);

                    const res: i64 = if (op.isArithmetic()) switch (op) {
                        .add => lhs + rhs,
                        .sub => lhs - rhs,
                        .mul => lhs * rhs,
                        .div => @intCast(a / b),
                        .mod => @intCast(a % b),
                        else => unreachable,
                    } else @intFromBool(switch (op) {
                        .cmp_lt => lhs < rhs,
                        .cmp_gt => lhs > rhs,
                        .cmp_le => lhs <= rhs,
                        .cmp_ge => lhs >= rhs,
                        .cmp_eq => lhs == rhs,
                        .cmp_ne => lhs != rhs,
                        else => unreachable,
                    });

                    try testRun(
                        &.{
                            VMInstruction.push(lhs),
                            VMInstruction.push(rhs),
                            VMInstruction{ .op = op },
                        },
                        "",
                        res,
                    );
                }
            }
        }
    };

    try util.testBinaryOp(.add);
    try util.testBinaryOp(.sub);
    try util.testBinaryOp(.mul);
    try util.testBinaryOp(.div);
    try util.testBinaryOp(.mod);

    try util.testBinaryOp(.cmp_lt);
    try util.testBinaryOp(.cmp_gt);
    try util.testBinaryOp(.cmp_le);
    try util.testBinaryOp(.cmp_ge);
    try util.testBinaryOp(.cmp_eq);
    try util.testBinaryOp(.cmp_ne);

    try testRun(
        &.{
            VMInstruction.push(0),
            VMInstruction.dup(),
            VMInstruction.pop(),
        },
        "",
        0,
    );

    // decrement value, starting at 10, until its zero, 10 is not special, any value should work
    try testRun(
        &.{
            VMInstruction.push(10),
            VMInstruction.push(1),
            VMInstruction.sub(),
            VMInstruction.dup(),
            VMInstruction.jmpnz(1),
        },
        "",
        0,
    );
}

test "fibonacci" {
    try testRun(&.{
        VMInstruction.push(10),
        VMInstruction.push(0),
        VMInstruction.push(1),
        VMInstruction.load(1),
        VMInstruction.dup(),
        VMInstruction.syscall(0),
        VMInstruction.load(2),
        VMInstruction.dup(),
        VMInstruction.store(1),
        VMInstruction.add(),
        VMInstruction.store(2),
        VMInstruction.load(0),
        VMInstruction.push(1),
        VMInstruction.sub(),
        VMInstruction.dup(),
        VMInstruction.store(0),
        VMInstruction.jmpnz(3),
        VMInstruction.pop(),
        VMInstruction.pop(),
        VMInstruction.pop(),
        VMInstruction.push(0),
    },
        \\0
        \\1
        \\1
        \\2
        \\3
        \\5
        \\8
        \\13
        \\21
        \\34
        \\
    , 0);
}
