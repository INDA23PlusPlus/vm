//!
//! Main interpreter
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("arch");
const Opcode = arch.Opcode;
const Instruction = arch.Instruction;
const Program = arch.Program;
const Type = @import("memory_manager").APITypes.Type;
const VMContext = @import("VMContext.zig");

fn assert(b: bool) !void {
    if (!b and std.debug.runtime_safety) {
        return error.AssertionFailed;
    }
}

fn doArithmetic(comptime T: type, a: T, op: Opcode, b: T) !T {
    if (T == Type.GetRepr(.int)) {
        return switch (op) {
            .add => a +% b,
            .sub => a -% b,
            .mul => a *% b,
            .div => if (b == 0 or (a == std.math.minInt(T) and b == -1)) error.InvalidOperation else @divTrunc(a, b),
            .mod => if (b == 0) error.InvalidOperation else if (b == -1) 0 else a - b * @divTrunc(a, b),
            else => unreachable,
        };
    } else {
        return switch (op) {
            .add => a + b,
            .sub => a - b,
            .mul => a * b,
            .div => a / b,
            .mod => if (b < 0) @rem(-a, -b) else @rem(a, b),
            else => unreachable,
        };
    }
}

fn doComparison(comptime T: type, a: T, op: Opcode, b: T) i64 {
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
        .string => std.mem.eql(u8, a.as(.string).?.get(), b.as(.string).?.get()),

        .list,
        .object,
        => std.debug.panic("TODO", .{}),
    };
}

fn doBinaryOp(a: Type, op: Opcode, b: Type) !Type {
    if (a.as(.int)) |ai| {
        if (b.as(.int)) |bi| {
            if (op.isArithmetic()) {
                return Type.from(try doArithmetic(Type.GetRepr(.int), ai, op, bi));
            } else if (op.isComparison()) {
                return Type.from(doComparison(Type.GetRepr(.int), ai, op, bi));
            } else {
                return error.InvalidOperation;
            }
        }
    }

    if (op.isArithmetic()) {
        return Type.from(try doArithmetic(Type.GetRepr(.float), try floatValue(a), op, try floatValue(b)));
    } else if (op.isComparison()) {
        return Type.from(doComparison(Type.GetRepr(.float), try floatValue(a), op, try floatValue(b)));
    } else {
        return error.InvalidOperation;
    }
}

fn take(ctxt: *VMContext, v: Type) Type {
    if (std.debug.runtime_safety) {
        ctxt.refc = ctxt.refc + 1;
    }

    return v.clone();
}

fn drop(ctxt: *VMContext, v: Type) void {
    if (std.debug.runtime_safety) {
        ctxt.refc = ctxt.refc - 1;
    }

    v.deinit();
}

fn get(ctxt: *VMContext, from_bp: bool, pos: i64) !Type {
    const base = if (from_bp) ctxt.bp else ctxt.stack.items.len;
    const idx: usize = if (pos < 0)
        base - @as(usize, @intCast(-pos))
    else
        base + @as(usize, @intCast(pos));

    assert(idx < ctxt.stack.items.len) catch |e| {
        std.debug.print("stack contents: {any}\n", .{ctxt.stack.items});
        return e;
    };

    return take(ctxt, ctxt.stack.items[idx]);
}

fn set(ctxt: *VMContext, from_bp: bool, pos: i64, v: Type) !void {
    const base = if (from_bp) ctxt.bp else ctxt.stack.items.len;
    const idx: usize = if (pos < 0)
        base - @as(usize, @intCast(-pos))
    else
        base + @as(usize, @intCast(pos));

    assert(idx < ctxt.stack.items.len) catch |e| {
        std.debug.print("stack contents: {any}\n", .{ctxt.stack.items});
        return e;
    };

    drop(ctxt, ctxt.stack.items[idx]);

    ctxt.stack.items[idx] = take(ctxt, v);
}

fn push(ctxt: *VMContext, v: Type) !void {
    try ctxt.stack.append(take(ctxt, v));
}

fn pop(ctxt: *VMContext) !Type {
    assert(ctxt.stack.items.len != 0) catch |e| {
        std.debug.print("stack contents: {any}\n", .{ctxt.stack.items});
        return e;
    };

    return ctxt.stack.pop();
}

fn opcodeToString(op: Opcode) []const u8 {
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
        .cmp_ne => "!=",
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
fn printImpl(x: *Type, ctxt: *VMContext) anyerror!void {
    const writer = ctxt.writer();
    switch (x.*) {
        .unit => try writer.print("()", .{}),
        .int => |i| try writer.print("{}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .string => |*s| try writer.print("{s}", .{s.get()}),
        .list => |*l| {
            const len = l.length();

            _ = try writer.write("[");
            for (0..len) |i| {
                if (i > 0) _ = try writer.write(", ");
                var tmp: Type = l.get(i).?;
                try printImpl(&tmp, ctxt);
            }
            _ = try writer.write("]");
        },
        .object => |*o| {
            var keys = o.keys();

            _ = try writer.write("{");
            var first = true;
            while (keys.next()) |k| {
                if (!first) _ = try writer.write(", ");
                var tmp: Type = o.get(k.*).?;
                try writer.print("{s}: ", .{ctxt.prog.field_names[@as(usize, k.*)]});
                try printImpl(&tmp, ctxt);
            }
            _ = try writer.write("}");
        },
    }
}

fn print(x: *Type, ctxt: *VMContext) !void {
    try printImpl(x, ctxt);
    _ = try ctxt.write("\n");
}

/// returns exit code of the program
pub fn run(ctxt: *VMContext) !i64 {
    while (ctxt.pc < ctxt.prog.code.len) {
        const i = ctxt.prog.code[ctxt.pc];

        if (ctxt.debug_output) {
            std.debug.print("@{}: {s}, sp: {}, bp: {}\n", .{ ctxt.pc, @tagName(i.op), ctxt.stack.items.len, ctxt.bp });
        }

        ctxt.pc += 1;

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
                var b = try pop(ctxt);
                defer drop(ctxt, b);
                var a = try pop(ctxt);
                defer drop(ctxt, a);

                const r = take(ctxt, try doBinaryOp(a, op, b));
                defer drop(ctxt, r);

                if (ctxt.debug_output) {
                    if (op.isArithmetic()) {
                        std.debug.print("arithmetic: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                    if (op.isComparison()) {
                        std.debug.print("comparison: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                }

                try push(ctxt, r);
            },
            // these have to be handled separately because they are valid for all types
            .cmp_eq,
            .cmp_ne,
            => |op| {
                var b = try pop(ctxt);
                defer drop(ctxt, b);
                var a = try pop(ctxt);
                defer drop(ctxt, a);

                const r = take(ctxt, Type.from(@intFromBool(switch (op) {
                    .cmp_eq => compareEq(a, b),
                    .cmp_ne => !compareEq(a, b),
                    else => unreachable,
                })));
                defer drop(ctxt, r);

                try push(ctxt, r);
            },
            .push => {
                const v = take(ctxt, Type.from(i.operand.int));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .pushf => {
                const v = take(ctxt, Type.from(i.operand.float));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .pushs => {
                const p = i.operand.location;
                try assert(p < ctxt.prog.strings.len);

                const v = take(ctxt, Type.from(ctxt.prog.strings[p]));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .pop => {
                drop(ctxt, try pop(ctxt));
            },
            .dup => {
                const v = try get(ctxt, false, -1);
                defer drop(ctxt, v);

                if (ctxt.debug_output) {
                    std.debug.print("duplicated: {}\n", .{v});
                }

                try push(ctxt, v);
            },
            .load => {
                const v = try get(ctxt, true, i.operand.int);
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .store => {
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                try set(ctxt, true, i.operand.int, v);
            },
            .syscall => {
                switch (i.operand.int) {
                    0 => {
                        var v = try pop(ctxt);
                        defer drop(ctxt, v);

                        try print(&v, ctxt);
                    },
                    else => {},
                }
            },
            .call => {
                const loc = i.operand.location;

                const ra = take(ctxt, Type.from(ctxt.pc));
                defer drop(ctxt, ra);

                const bp = take(ctxt, Type.from(ctxt.bp));
                defer drop(ctxt, bp);

                try push(ctxt, bp);
                try push(ctxt, ra);

                ctxt.bp = ctxt.stack.items.len;
                ctxt.pc = loc;
            },
            .ret => {
                const r = try pop(ctxt);
                defer drop(ctxt, r);

                while (ctxt.stack.items.len != ctxt.bp) {
                    drop(ctxt, try pop(ctxt));
                }

                if (ctxt.bp == 0) {
                    try push(ctxt, r);

                    break;
                } else {
                    const ra = try pop(ctxt);
                    defer drop(ctxt, ra);

                    const bp = try pop(ctxt);
                    defer drop(ctxt, bp);

                    const N = try pop(ctxt);
                    defer drop(ctxt, N);

                    try assert(ra.tag() == .int);
                    try assert(bp.tag() == .int);
                    try assert(N.tag() == .int);

                    if (ctxt.debug_output) {
                        std.debug.print("popping {} items, sp: {}, bp: {}\n", .{ N, ctxt.stack.items.len, ctxt.bp });
                    }

                    for (0..@intCast(N.int)) |_| {
                        drop(ctxt, try pop(ctxt));
                    }

                    try push(ctxt, r);

                    ctxt.bp = @intCast(bp.int);
                    ctxt.pc = @intCast(ra.int);
                }
            },
            .jmp => {
                const loc = i.operand.location;

                if (ctxt.debug_output) {
                    std.debug.print("jumping to: {}\n", .{loc});
                }

                ctxt.pc = loc;
            },
            .jmpnz => {
                const loc = i.operand.location;
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                try assert(v.tag() == .int);

                if (v.int != 0) {
                    if (ctxt.debug_output) {
                        std.debug.print("took branch to: {}\n", .{loc});
                    }

                    ctxt.pc = loc;
                } else {
                    if (ctxt.debug_output) {
                        std.debug.print("didn't take branch to: {}\n", .{loc});
                    }
                }
            },
            else => std.debug.panic("unimplemented instruction {}\n", .{i}),
        }
    }

    var r: Type.GetRepr(.int) = undefined;
    {
        const rv = try pop(ctxt);
        defer drop(ctxt, rv);

        r = rv.as(.int) orelse return error.NonIntReturnValue;
    }

    assert(ctxt.refc == ctxt.stack.items.len) catch |e| {
        std.debug.print("unbalanced refc: {} != {}\n", .{ ctxt.refc, ctxt.stack.items.len });
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

fn testRun(prog: Program, expected_output: []const u8, expected_exit_code: i64) !void {
    const output_buffer = try std.testing.allocator.alloc(u8, expected_output.len * 2);
    defer std.testing.allocator.free(output_buffer);
    var output_stream = std.io.fixedBufferStream(output_buffer);
    const output_writer = output_stream.writer();

    var ctxt = VMContext.init(prog, std.testing.allocator, &output_writer, false);
    defer ctxt.deinit();

    try std.testing.expectEqual(expected_exit_code, try run(&ctxt));

    const a = try replaceWhiteSpace(expected_output, std.testing.allocator);
    defer std.testing.allocator.free(a);
    const b = try replaceWhiteSpace(output_stream.getWritten(), std.testing.allocator);
    defer std.testing.allocator.free(b);

    try std.testing.expect(std.mem.eql(u8, a, b));
}

test "arithmetic" {
    const util = struct {
        fn testBinaryOp(op: Opcode) !void {
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
                        Program.init(&.{
                            Instruction.push(lhs),
                            Instruction.push(rhs),
                            Instruction{ .op = op },
                        }, 0, &.{}, &.{}),
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
        Program.init(&.{
            Instruction.push(0),
            Instruction.dup(),
            Instruction.pop(),
        }, 0, &.{}, &.{}),
        "",
        0,
    );

    // decrement value, starting at 10, until its zero, 10 is not special, any value should work
    try testRun(
        Program.init(&.{
            Instruction.push(10),
            Instruction.push(1),
            Instruction.sub(),
            Instruction.dup(),
            Instruction.jmpnz(1),
        }, 0, &.{}, &.{}),
        "",
        0,
    );

    // ensure a/b*b + a%b == a
    for (0..201) |i| {
        for (0..201) |j| {
            const a = @as(i64, @intCast(i)) - 100;
            const b = @as(i64, @intCast(j)) - 100;
            if (b == 0) continue;

            try testRun(Program.init(&.{
                Instruction.push(a),
                Instruction.push(b),
                Instruction.div(),
                // stack is now a / b

                Instruction.push(b),
                Instruction.mul(),
                // stack is now a / b * b

                Instruction.push(a),
                Instruction.push(b),
                Instruction.mod(),
                // stack is now a/b*b, a%b

                Instruction.add(),
                // stack should now be just a

                Instruction.push(a),
                Instruction.equal(),
                Instruction.ret(),
                // ensure stack is actually just a
            }, 0, &.{}, &.{}), "", 1);
        }
    }
}

test "fibonacci" {
    try testRun(Program.init(&.{
        Instruction.push(10),
        Instruction.push(0),
        Instruction.push(1),
        Instruction.load(1),
        Instruction.dup(),
        Instruction.syscall(0),
        Instruction.load(2),
        Instruction.dup(),
        Instruction.store(1),
        Instruction.add(),
        Instruction.store(2),
        Instruction.load(0),
        Instruction.push(1),
        Instruction.sub(),
        Instruction.dup(),
        Instruction.store(0),
        Instruction.jmpnz(3),
        Instruction.pop(),
        Instruction.pop(),
        Instruction.pop(),
        Instruction.push(0),
    }, 0, &.{}, &.{}),
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

test "recursive fibonacci" {
    try testRun(Program.init(&.{
        Instruction.push(10),
        Instruction.push(1),
        Instruction.call(4),
        Instruction.ret(),
        Instruction.load(-4),
        Instruction.push(2),
        Instruction.less(),
        Instruction.jmpnz(20),
        Instruction.load(-4),
        Instruction.push(1),
        Instruction.sub(),
        Instruction.push(1),
        Instruction.call(4),
        Instruction.load(-4),
        Instruction.push(2),
        Instruction.sub(),
        Instruction.push(1),
        Instruction.call(4),
        Instruction.add(),
        Instruction.ret(),
        Instruction.load(-4),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 55);

    const Asm = @import("asm").Asm;
    const AsmError = @import("asm").Error;
    var errors = std.ArrayList(AsmError).init(std.testing.allocator);
    defer errors.deinit();

    const source =
        \\-function "main"
        \\-begin
        \\push %10
        \\push %1
        \\call "fib"
        \\ret
        \\-end
        \\
        \\-function "fib"
        \\-begin
        \\load %-4
        \\push %2
        \\cmp_lt
        \\jmpnz .foo
        \\load %-4
        \\push %1
        \\sub
        \\push %1
        \\call "fib"
        \\load %-4
        \\push %2
        \\sub
        \\push %1
        \\call "fib"
        \\add
        \\ret
        \\.foo
        \\load %-4
        \\ret
        \\-end
    ;

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();
    try assert(errors.items.len == 0);
    try testRun(asm_.getProgram(), "", 55);
}

test "hello world" {
    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.syscall(0),
        Instruction.push(0),
    }, 0, &.{"Hello World!"}, &.{}), "Hello World!", 0);
}

test "string compare" {
    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.equal(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.equal(),
    }, 0, &.{ "bar", "baz" }, &.{}), "", 0);
}
