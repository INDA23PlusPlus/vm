//!
//! Main interpreter
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("arch");
const Opcode = arch.Opcode;
const Instruction = arch.Instruction;
const Program = arch.Program;
const RtError = arch.err.RtError;
const Mem = @import("memory_manager");
const Value = Mem.APITypes.Value;
const VMContext = @import("VMContext.zig");
const jit_mod = @import("jit");

fn assert(b: bool) !void {
    if (!b and std.debug.runtime_safety) {
        return error.AssertionFailed;
    }
}

inline fn doArithmetic(comptime T: type, a: T, op: Opcode, b: T, ctxt: *VMContext) !Value {
    return switch (op) {
        .add => if (T == Value.GetRepr(.int)) Value.from(a +% b) else Value.from(a + b),
        .sub => if (T == Value.GetRepr(.int)) Value.from(a -% b) else Value.from(a - b),
        .mul => if (T == Value.GetRepr(.int)) Value.from(a *% b) else Value.from(a * b),
        .bit_or => if (T == Value.GetRepr(.int)) Value.from(a | b) else blk: {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{
                    .invalid_binop = .{
                        .lt = .float,
                        .op = op,
                        .rt = .float,
                    },
                },
            };
            break :blk error.RuntimeError;
        },
        .bit_xor => if (T == Value.GetRepr(.int)) Value.from(a ^ b) else blk: {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{
                    .invalid_binop = .{
                        .lt = .float,
                        .op = op,
                        .rt = .float,
                    },
                },
            };
            break :blk error.RuntimeError;
        },
        .bit_and => if (T == Value.GetRepr(.int)) Value.from(a & b) else blk: {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{
                    .invalid_binop = .{
                        .lt = .float,
                        .op = op,
                        .rt = .float,
                    },
                },
            };
            break :blk error.RuntimeError;
        },
        .log_and => if (T == Value.GetRepr(.int)) Value.from(a != 0 and b != 0) else blk: {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{
                    .invalid_binop = .{
                        .lt = .float,
                        .op = op,
                        .rt = .float,
                    },
                },
            };
            break :blk error.RuntimeError;
        },
        .log_or => if (T == Value.GetRepr(.int)) Value.from(a != 0 or b != 0) else blk: {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{
                    .invalid_binop = .{
                        .lt = .float,
                        .op = op,
                        .rt = .float,
                    },
                },
            };
            break :blk error.RuntimeError;
        },
        .div => blk: {
            if (T == Value.GetRepr(.int)) {
                if (b == 0 or (a == std.math.minInt(T) and b == -1)) {
                    ctxt.rterror = .{ .pc = ctxt.pc - 1, .err = .division_by_zero };
                    return error.RuntimeError;
                }
            }
            break :blk if (T == Value.GetRepr(.int)) Value.from(@divTrunc(a, b)) else Value.from(a / b);
        },
        .mod => blk: {
            if (T == Value.GetRepr(.int)) {
                if (b == 0 or (a == std.math.minInt(T) and b == -1)) {
                    ctxt.rterror = .{ .pc = ctxt.pc - 1, .err = .division_by_zero };
                    return error.RuntimeError;
                }
            }
            break :blk Value.from(a - b * @divTrunc(a, b));
        },
        .cmp_eq => Value.from(a == b),
        .cmp_ne => Value.from(a != b),
        .cmp_lt => Value.from(a < b),
        .cmp_le => Value.from(a <= b),
        .cmp_gt => Value.from(a > b),
        .cmp_ge => Value.from(a >= b),
        else => unreachable,
    };
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

fn listEq(a: Value, b: Value) bool {
    const l = a.list;
    const r = b.list;
    if (l.ref == r.ref) {
        return true;
    }

    const len = l.length();
    if (r.length() != len) return false;

    for (0..len) |i| {
        if (!compareEq(l.get(i), r.get(i))) return false;
    }

    return true;
}

fn objectEq(a: Value, b: Value) bool {
    const l = a.object;
    const r = b.object;
    if (l.ref == r.ref) {
        return true;
    }

    var lentries = l.entries();
    while (lentries.next()) |entry| {
        const cmp = r.get(entry.key_ptr.*) orelse return false;
        if (!compareEq(entry.value_ptr.*, cmp)) return false;
    }
    var rentries = l.entries();
    while (rentries.next()) |entry| {
        const cmp = l.get(entry.key_ptr.*) orelse return false;
        if (!compareEq(entry.value_ptr.*, cmp)) return false;
    }
    return true;
}

fn getstr(a: Value) []const u8 {
    assert(a == .string_ref or a == .string_lit) catch {
        debug_log("internal error: called getstr on non string\n", .{});
    };
    return if (a == .string_lit) a.string_lit.* else a.string_ref.get();
}

fn stringOperation(a: Value, op: Opcode, b: Value, ctxt: *VMContext) !Value {
    const lhs = getstr(a);
    const rhs = getstr(b);

    const order = std.mem.order(u8, lhs, rhs);
    return Value.from(@intFromBool(switch (op) {
        .cmp_eq => order == .eq,
        .cmp_ne => order != .eq,

        .cmp_ge => order != .lt,
        .cmp_gt => order == .gt,

        .cmp_le => order != .gt,
        .cmp_lt => order == .lt,

        else => {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{ .invalid_binop = .{ .lt = a.tag(), .op = op, .rt = b.tag() } },
            };
            !return error.RuntimeError;
        },
    }));
}

fn compareEq(a: Value, b: Value) bool {
    if (a.tag() != b.tag()) {
        if (a.tag() == .unit or b.tag() == .unit) return false;
        const af = floatValue(a) catch unreachable;
        const bf = floatValue(b) catch unreachable;
        return af == bf;
    }

    return switch (a.tag()) {
        .unit => true,
        .int => a.as(.int).? == b.as(.int).?,
        .float => a.as(.float).? == b.as(.float).?,
        .string_ref, .string_lit => std.mem.order(u8, getstr(a), getstr(b)) == .eq,
        .list => listEq(a, b),
        .object => objectEq(a, b),
    };
}

fn doBinaryOpSameType(a: Value, op: Opcode, b: Value, ctxt: *VMContext) !Value {
    return switch (a.tag()) {
        .unit => Value.tryFrom(doArithmetic(Value.GetRepr(.int), 0, op, 0, ctxt)),
        .int => Value.tryFrom(doArithmetic(Value.GetRepr(.int), a.int, op, b.int, ctxt)),
        .float => Value.tryFrom(doArithmetic(Value.GetRepr(.float), a.float, op, b.float, ctxt)),
        .string_ref, .string_lit => stringOperation(a, op, b, ctxt),
        .list => switch (op) {
            .cmp_eq => Value.from(listEq(a, b)),
            .cmp_ne => Value.from(!listEq(a, b)),
            else => err: {
                ctxt.rterror = .{
                    .pc = ctxt.pc - 1,
                    .err = .{ .invalid_binop = .{ .lt = a.tag(), .op = op, .rt = b.tag() } },
                };
                break :err error.RuntimeError;
            },
        },
        .object => switch (op) {
            .cmp_eq => Value.from(objectEq(a, b)),
            .cmp_ne => Value.from(!objectEq(a, b)),
            else => err: {
                ctxt.rterror = .{
                    .pc = ctxt.pc - 1,
                    .err = .{ .invalid_binop = .{ .lt = a.tag(), .op = op, .rt = b.tag() } },
                };
                break :err error.RuntimeError;
            },
        },
    };
}

inline fn doBinaryOp(a: Value, op: Opcode, b: Value, ctxt: *VMContext) !Value {
    if (a.tag() == b.tag()) {
        return doBinaryOpSameType(a, op, b, ctxt);
    }

    // if a and b are different type and theyre not `int` and `float` or `string_lit` and `string_ref` it's invalid and should end up triggering this
    if (@intFromEnum(a) ^ @intFromEnum(b) >= 2) {
        ctxt.rterror = .{
            .pc = ctxt.pc - 1,
            .err = .{ .invalid_binop = .{ .lt = a.tag(), .op = op, .rt = b.tag() } },
        };
        return error.RuntimeError;
    }

    // only valid types from here on out, could still be invalid if you try to add lists for example
    const float = Value.GetRepr(.float);
    if (a.as(.int)) |ai| {
        const af: float = @floatFromInt(ai);
        const bf: float = b.float;
        return Value.tryFrom(doArithmetic(float, af, op, bf, ctxt));
    }

    if (b.as(.int)) |bi| {
        const af: float = a.float;
        const bf: float = @floatFromInt(bi);
        return Value.tryFrom(doArithmetic(float, af, op, bf, ctxt));
    }

    if ((@intFromEnum(a) | @intFromEnum(b)) ^ 0b10000 < 2) {
        return stringOperation(a, op, b, ctxt);
    }

    return error.RuntimeError;
}

fn take(ctxt: *VMContext, v: Value) Value {
    if (std.debug.runtime_safety) {
        ctxt.refc = ctxt.refc + 1;
    }

    return v;
}

fn drop(ctxt: *VMContext, v: Value) void {
    if (std.debug.runtime_safety) {
        ctxt.refc = ctxt.refc - 1;
    }

    _ = v;
}

inline fn get(ctxt: *VMContext, from_bp: bool, pos: i64) !Value {
    const base = if (from_bp) ctxt.bp else ctxt.stack.items.len;
    const idx: usize = if (pos < 0)
        base - @as(usize, @intCast(-pos))
    else
        base + @as(usize, @intCast(pos));

    assert(idx < ctxt.stack.items.len) catch |e| {
        std.debug.print("stack contents: {any}\n", .{ctxt.stack.items});
        return e;
    };

    return ctxt.stack.items[idx];
}

inline fn unlikely_event() void {
    @setCold(true);
}

// mark condition as unlikely (optimizer hint)
inline fn unlikely(a: bool) bool {
    if (a) unlikely_event();
    return a;
}

// mark condition as likely (optimizer hint)
inline fn likely(a: bool) bool {
    return !unlikely(!a);
}

inline fn set(ctxt: *VMContext, from_bp: bool, pos: i64, v: Value) !void {
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

fn push(ctxt: *VMContext, v: Value) !void {
    if (unlikely(ctxt.stack.capacity == ctxt.stack.items.len)) {
        try ctxt.stack.ensureTotalCapacityPrecise(ctxt.stack.items.len * 2);
    }
    ctxt.stack.appendAssumeCapacity(take(ctxt, v));
}

fn pop(ctxt: *VMContext) !Value {
    assert(ctxt.stack.items.len != 0) catch |e| {
        std.debug.print("stack contents: {any}\n", .{ctxt.stack.items});
        return e;
    };

    return ctxt.stack.pop();
}

fn jit_compile_full(ctxt: *VMContext) !void {
    if (ctxt.jit_fn) |*jit_fn| {
        jit_fn.deinit();
    }

    var jit = jit_mod.Jit.init(ctxt.alloc);
    defer jit.deinit();

    var jit_fn = try jit.compile_program(ctxt.prog, null);
    jit_fn.set_writer(@as(*const VMContext, ctxt));

    ctxt.jit_fn = jit_fn;
}

fn jit_compile_partial(ctxt: *VMContext) !void {
    if (ctxt.jit_fn) |*jit_fn| {
        jit_fn.deinit();
    }

    var jit = jit_mod.Jit.init(ctxt.alloc);
    defer jit.deinit();

    var fns = std.ArrayList([]const Instruction).init(ctxt.alloc);
    defer fns.deinit();

    if (ctxt.prog.fn_tbl) |fn_tbl| {
        for (fn_tbl.items) |sym| {
            if (ctxt.jit_mask.isSet(sym.addr)) {
                try fns.append(ctxt.prog.code[sym.addr..(sym.addr + sym.size)]);
            }
        }
    }

    var jit_fn = try jit.compile_partial(ctxt.prog, fns.items, null);
    jit_fn.set_writer(@as(*const VMContext, ctxt));

    ctxt.jit_fn = jit_fn;
}

fn is_jitable_call(ctxt: *VMContext) bool {
    if (ctxt.stack.items.len == 0) {
        return false;
    }

    const N_val = ctxt.stack.items[ctxt.stack.items.len - 1];
    if (N_val != .int) {
        return false;
    }
    const N: usize = @intCast(N_val.int);

    if (N + 1 > ctxt.stack.items.len) {
        return false;
    }

    for (0..N) |i| {
        if (ctxt.stack.items[ctxt.stack.items.len - 2 - i] != .int) {
            return false;
        }
    }

    return true;
}

fn opcodeToString(op: Opcode) []const u8 {
    return switch (op) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .bit_and => "&",
        .bit_or => "|",
        .bit_xor => "^",
        .bit_not => "~",
        .log_and => "&&",
        .log_or => "||",
        .log_not => "!",
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

fn printImpl(x: *Value, ctxt: *VMContext) anyerror!void {
    const writer = ctxt.writer();
    switch (x.*) {
        .unit => try writer.print("()", .{}),
        .int => |i| try writer.print("{}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .string_lit, .string_ref => try writer.print("{s}", .{getstr(x.*)}),
        .list => |*l| {
            const len = l.length();

            _ = try writer.write("[");
            for (0..len) |i| {
                if (i > 0) _ = try writer.write(", ");
                var tmp: Value = l.get(i);
                try printImpl(&tmp, ctxt);
            }
            _ = try writer.write("]");
        },
        .object => |*o| {
            var keys = o.keys();

            var fields = std.ArrayList(usize).init(ctxt.alloc);
            defer fields.deinit();

            while (keys.next()) |k| {
                try fields.append(k.*);
            }

            const sortUtils = struct {
                pub fn less(_: @TypeOf(.{}), a: usize, b: usize) bool {
                    return a < b;
                }
            };

            std.sort.pdq(usize, fields.items, .{}, sortUtils.less);

            _ = try writer.write("{");
            var first = true;
            for (fields.items) |k| {
                if (!first) _ = try writer.write(", ");
                first = false;
                var tmp: Value = o.get(k).?;
                try writer.print("{s}: ", .{ctxt.prog.field_names[k]});
                try printImpl(&tmp, ctxt);
            }
            _ = try writer.write("}");
        },
    }
}

fn printLn(x: *Value, ctxt: *VMContext) !void {
    try printImpl(x, ctxt);
    _ = try ctxt.write("\n");
    try ctxt.flush();
}

fn print(x: *Value, ctxt: *VMContext) !void {
    try printImpl(x, ctxt);
}

// wrapper around std.debug.print, but marked as cold as a hint to the optimizer
noinline fn debug_log(comptime fmt: []const u8, args: anytype) void {
    @setCold(true);
    std.debug.print(fmt, args);
}

/// returns exit code of the program
pub fn run(ctxt: *VMContext) !i64 {
    defer ctxt.reset();
    if (ctxt.jit_enabled and ctxt.jit_mask.isSet(ctxt.pc)) {
        if (ctxt.jit_fn == null) {
            try jit_compile_full(ctxt);
        }
        if (ctxt.debug_output) {
            debug_log("Running whole program compiled\n", .{});
        }
        return ctxt.jit_fn.?.execute() catch |e| {
            ctxt.rterror = ctxt.jit_fn.?.rterror;
            return e;
        };
    }

    try ctxt.stack.ensureTotalCapacity(1); // skip branch in reallocation
    var mem = try Mem.MemoryManager.init(ctxt.alloc, &ctxt.stack);
    defer mem.deinit();
    while (true) {
        if (ctxt.pc >= ctxt.prog.code.len) {
            return error.InvalidProgramCounter;
        }
        const insn = ctxt.prog.code[ctxt.pc];
        if (ctxt.debug_output) {
            debug_log("@{}: {s}, sp: {}, bp: {}\n", .{ ctxt.pc, @tagName(insn.op), ctxt.stack.items.len, ctxt.bp });
        }

        ctxt.pc += 1;
        // fastpath for integer math
        if (@intFromEnum(insn.op) < @intFromEnum(arch.Opcode.jmp)) {
            const stack_items = ctxt.stack.items;
            const stack_len = stack_items.len;
            if (insn.op == .inc) {
                stack_items[stack_len - 1].int += 1;
                continue;
            } else if (insn.op == .dec) {
                stack_items[stack_len - 1].int -= 1;
                continue;
            } else if ((stack_items.len >= 2) and (@intFromEnum(stack_items[stack_len - 2]) | @intFromEnum(stack_items[stack_len - 1]) == @intFromEnum(Value.int))) {
                const lhs = stack_items[stack_len - 2];
                const rhs = stack_items[stack_len - 1];
                try assert(lhs.is(.int));
                try assert(rhs.is(.int));
                const a = lhs.int;
                const b = rhs.int;
                stack_items[stack_len - 2] = try doArithmetic(Value.GetRepr(.int), a, insn.op, b, ctxt);
                drop(ctxt, try pop(ctxt));
                continue;
            }
        }
        switch (insn.op) {
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .log_or,
            .log_and,
            .bit_or,
            .bit_xor,
            .bit_and,
            .cmp_lt,
            .cmp_gt,
            .cmp_le,
            .cmp_ge,
            .cmp_eq,
            .cmp_ne,
            => |op| {
                const b = try pop(ctxt);
                defer drop(ctxt, b);
                const a = try pop(ctxt);
                defer drop(ctxt, a);

                const r = try doBinaryOp(a, op, b, ctxt);

                if (ctxt.debug_output) {
                    if (op.isArithmetic()) {
                        debug_log("arithmetic: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                    if (op.isComparison()) {
                        debug_log("comparison: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                    if (op.isLogical()) {
                        debug_log("logical: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                    if (op.isBitwise()) {
                        debug_log("bitwise: {} {s} {} = {}\n", .{ a, opcodeToString(op), b, r });
                    }
                }

                try push(ctxt, r);
            },
            .inc => {
                try assert(ctxt.stack.items.len > 0);
                const v = ctxt.stack.getLast();
                if (v.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_unop = .{ .t = v.tag(), .op = insn.op } },
                    };
                    return error.RuntimeError;
                }
                ctxt.stack.items[ctxt.stack.items.len - 1].int += 1;
            },
            .dec => {
                try assert(ctxt.stack.items.len > 0);
                const v = ctxt.stack.getLast();
                if (v.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_unop = .{ .t = v.tag(), .op = insn.op } },
                    };
                    return error.RuntimeError;
                }
                ctxt.stack.items[ctxt.stack.items.len - 1].int -= 1;
            },
            .neg => {
                try assert(ctxt.stack.items.len > 0);
                const v = ctxt.stack.getLast();
                if (v != .int and v != .float) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_unop = .{ .t = v.tag(), .op = insn.op } },
                    };
                    return error.RuntimeError;
                }

                if (v == .int) {
                    ctxt.stack.items[ctxt.stack.items.len - 1].int *= -1;
                } else {
                    ctxt.stack.items[ctxt.stack.items.len - 1].float *= -1.0;
                }
            },
            .log_not => {
                try assert(ctxt.stack.items.len > 0);
                const v = ctxt.stack.getLast();
                if (v.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_unop = .{ .t = v.tag(), .op = insn.op } },
                    };
                    return error.RuntimeError;
                }
                ctxt.stack.items[ctxt.stack.items.len - 1].int = @intFromBool(ctxt.stack.items[ctxt.stack.items.len - 1].int != 0);
            },
            .bit_not => {
                try assert(ctxt.stack.items.len > 0);
                const v = ctxt.stack.getLast();
                if (v.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_unop = .{ .t = v.tag(), .op = insn.op } },
                    };
                    return error.RuntimeError;
                }
                ctxt.stack.items[ctxt.stack.items.len - 1].int = ~ctxt.stack.items[ctxt.stack.items.len - 1].int;
            },
            .push => try push(ctxt, Value.from(insn.operand.int)),
            .pushf => try push(ctxt, Value.from(insn.operand.float)),
            .pushs => {
                const p = insn.operand.location;
                try assert(p < ctxt.prog.strings.len);

                const v = take(ctxt, Value.from(&ctxt.prog.strings[p]));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .pop => {
                drop(ctxt, try pop(ctxt));
            },
            .dup => {
                const v = try get(ctxt, false, -1);

                if (ctxt.debug_output) {
                    debug_log("duplicated: {}\n", .{v});
                }

                try push(ctxt, v);
            },
            .load => {
                const v = try get(ctxt, true, insn.operand.int);
                try push(ctxt, v);
            },
            .store => {
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                try set(ctxt, true, insn.operand.int, v);
            },
            .syscall => {
                switch (insn.operand.int) {
                    0 => {
                        var v = try pop(ctxt);
                        defer drop(ctxt, v);

                        try printLn(&v, ctxt);
                    },
                    1 => {
                        var v = try pop(ctxt);
                        defer drop(ctxt, v);

                        try print(&v, ctxt);
                    },
                    2 => {
                        try ctxt.flush();
                    },
                    else => |c| {
                        ctxt.rterror = .{
                            .pc = ctxt.pc - 1,
                            .err = .{ .undefined_syscall = c },
                        };
                        return error.RuntimeError;
                    },
                }
            },
            .call => {
                const loc = insn.operand.location;

                if (ctxt.jit_enabled and ctxt.jit_mask.isSet(loc) and is_jitable_call(ctxt)) {
                    const N_val = try pop(ctxt);
                    defer drop(ctxt, N_val);

                    try assert(N_val.tag() == .int);
                    const N: usize = @intCast(N_val.int);

                    try ctxt.jit_args.resize(N);

                    if (ctxt.debug_output) {
                        debug_log("popping {} items, sp: {}, bp: {}\n", .{ N_val, ctxt.stack.items.len, ctxt.bp });
                    }

                    for (0..N) |i| {
                        const v = try pop(ctxt);
                        ctxt.jit_args.items[i] = v.int;
                        drop(ctxt, v);
                    }

                    if (ctxt.jit_fn == null) {
                        try jit_compile_partial(ctxt);
                    }

                    if (ctxt.debug_output) {
                        debug_log("Running compiled function at {}.\n", .{loc});
                    }
                    const r = ctxt.jit_fn.?.execute_sub(loc, ctxt.jit_args.items) catch |e| {
                        ctxt.rterror = ctxt.jit_fn.?.rterror;
                        return e;
                    };

                    try push(ctxt, Value.from(r));
                } else {
                    const ra = Value.from(ctxt.pc);
                    const bp = Value.from(ctxt.bp);

                    try push(ctxt, bp);
                    try push(ctxt, ra);

                    ctxt.bp = ctxt.stack.items.len;
                    ctxt.pc = loc;
                }
            },
            .ret => {
                const r = try pop(ctxt);
                defer drop(ctxt, r);

                for (ctxt.bp..ctxt.stack.items.len) |idx| {
                    drop(ctxt, ctxt.stack.items[idx]);
                }
                try ctxt.stack.resize(ctxt.bp);

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
                        debug_log("popping {} items, sp: {}, bp: {}\n", .{ N, ctxt.stack.items.len, ctxt.bp });
                    }

                    // ctxt.stack.shrinkRetainingCapacity(ctxt.stack.items.len - @as(usize, @intCast(N.int)));
                    for (0..@intCast(N.int)) |_| {
                        drop(ctxt, try pop(ctxt));
                    }

                    try push(ctxt, r);

                    ctxt.bp = @intCast(bp.int);
                    ctxt.pc = @intCast(ra.int);
                }
            },
            .jmp => {
                const loc = insn.operand.location;

                if (ctxt.debug_output) {
                    debug_log("jumping to: {}\n", .{loc});
                }

                ctxt.pc = loc;
            },
            .jmpnz => {
                const loc = insn.operand.location;
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                try assert(v.tag() == .int);

                ctxt.pc = if (v.int != 0) loc else ctxt.pc;
                if (ctxt.debug_output) {
                    if (v.int != 0) {
                        debug_log("took branch to: {}\n", .{loc});
                    } else {
                        debug_log("didn't take branch to: {}\n", .{loc});
                    }
                }
            },
            .stack_alloc => {
                const v = Value.from(void{});

                const n: usize = @intCast(insn.operand.int);
                try assert(n >= 0);

                try ctxt.stack.ensureTotalCapacity(ctxt.stack.items.len + n);
                for (0..@as(usize, @intCast(n))) |_| {
                    push(ctxt, v) catch unreachable;
                }
            },
            .list_alloc => {
                const s = mem.alloc_list();
                defer s.deinit();

                const v = take(ctxt, Value.from(s));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .list_store => {
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                const idx = try pop(ctxt);
                defer drop(ctxt, idx);

                if (idx.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_index_type = idx },
                    };
                    return error.RuntimeError;
                }

                const index = @as(usize, @intCast(idx.asUnChecked(.int)));

                const s = try pop(ctxt);
                defer drop(ctxt, s);

                if (s.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_indexing = s.tag() },
                    };
                    return error.RuntimeError;
                }

                const list = s.asUnChecked(.list);

                list.set(index, v);
            },
            .list_load => {
                const idx = try pop(ctxt);
                defer drop(ctxt, idx);

                if (idx.tag() != .int) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .invalid_index_type = idx.tag() },
                    };
                    return error.RuntimeError;
                }

                const index = @as(usize, @intCast(idx.asUnChecked(.int)));

                const s = try pop(ctxt);

                if (s.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_indexing = s.tag() },
                    };
                    return error.RuntimeError;
                }

                defer drop(ctxt, s);
                const list = s.asUnChecked(.list);

                const v = take(ctxt, Value.from(list.get(index)));
                defer drop(ctxt, v);

                try push(ctxt, v);
            },
            .list_length => {
                const l = try pop(ctxt);
                if (l.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_length = l.tag() },
                    };
                    return error.RuntimeError;
                }

                defer drop(ctxt, l);
                const list = l.asUnChecked(.list);

                const len = take(ctxt, Value.from(list.length()));
                defer drop(ctxt, len);
                try push(ctxt, len);
            },
            .list_append => {
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                const l = try pop(ctxt);
                if (l.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_append = l.tag() },
                    };
                    return error.RuntimeError;
                }

                defer drop(ctxt, l);
                var list = l.asUnChecked(.list);

                try list.push(v);
            },
            .list_pop => {
                const l = try pop(ctxt);
                if (l.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_indexing = l.tag() },
                    };
                    return error.RuntimeError;
                }
                defer drop(ctxt, l);
                const list = l.asUnChecked(.list);

                try push(ctxt, list.pop());
            },
            .list_remove => {
                const idx = try pop(ctxt);
                defer drop(ctxt, idx);
                try assert(idx.is(.int));
                const index = @as(usize, @intCast(idx.asUnChecked(.int)));

                const l = try pop(ctxt);
                if (l.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_list_indexing = l.tag() },
                    };
                    return error.RuntimeError;
                }
                defer drop(ctxt, l);
                const list = l.asUnChecked(.list);

                try list.remove(index);
            },
            .list_concat => {
                const l_1 = try pop(ctxt);
                const l_2 = try pop(ctxt);
                if (l_1.tag() != .list or l_2.tag() != .list) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{
                            .invalid_binop = .{
                                .lt = l_1.tag(),
                                .op = insn.op,
                                .rt = l_2.tag(),
                            },
                        },
                    };
                    return error.RuntimeError;
                }

                defer drop(ctxt, l_1);
                defer drop(ctxt, l_2);

                const list_1 = l_1.asUnChecked(.list);
                const list_2 = l_2.asUnChecked(.list);

                try list_2.concat(&list_1);
                try push(ctxt, Value.from(list_2));
            },
            .struct_alloc => {
                const s = mem.alloc_struct();

                try push(ctxt, Value.from(s));
            },
            .struct_store => {
                const v = try pop(ctxt);
                defer drop(ctxt, v);

                const f = insn.operand.field_id;
                const s = try pop(ctxt);
                defer drop(ctxt, s);

                if (s.tag() != .object) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_struct_field_access = s.tag() },
                    };
                    return error.RuntimeError;
                }

                const obj = s.asUnChecked(.object);
                try obj.set(f, v);
            },
            .struct_load => {
                const f = insn.operand.field_id;

                const s = try pop(ctxt);
                defer drop(ctxt, s);

                if (s.tag() != .object) {
                    ctxt.rterror = .{
                        .pc = ctxt.pc - 1,
                        .err = .{ .non_struct_field_access = s.tag() },
                    };
                    return error.RuntimeError;
                }

                const obj = s.asUnChecked(.object);
                const v = Value.from(obj.get(f));

                try push(ctxt, v);
            },
        }
    }

    var r: Value.GetRepr(.int) = undefined;
    {
        const rv = try pop(ctxt);
        defer drop(ctxt, rv);

        r = rv.as(.int) orelse {
            ctxt.rterror = .{
                .pc = ctxt.pc - 1,
                .err = .{ .non_int_main_ret_val = rv.tag() },
            };
            return error.RuntimeError;
        };
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
    return testRunWithJit(prog, expected_output, expected_exit_code, .off);
}

fn testRunWithJit(prog: Program, expected_output: []const u8, expected_exit_code: i64, jit_req: enum { full, partial, none, off }) !void {
    const output_buffer = try std.testing.allocator.alloc(u8, expected_output.len * 2 + 1024);
    defer std.testing.allocator.free(output_buffer);
    var output_stream = std.io.fixedBufferStream(output_buffer);
    const output_writer = output_stream.writer();

    var ctxt = try VMContext.init(prog, std.testing.allocator, &output_writer, &std.io.getStdErr().writer(), false);
    defer ctxt.deinit();

    if (jit_req != .off) {
        const jit_val: @TypeOf(jit_req) = if (ctxt.jit_mask.isSet(prog.entry)) .full else if (ctxt.jit_mask.count() != 0) .partial else .none;
        try std.testing.expectEqual(jit_req, jit_val);
    } else {
        ctxt.jit_enabled = false;
    }

    try std.testing.expectEqual(expected_exit_code, try run(&ctxt));

    const a = try replaceWhiteSpace(expected_output, std.testing.allocator);
    defer std.testing.allocator.free(a);
    const b = try replaceWhiteSpace(output_stream.getWritten(), std.testing.allocator);
    defer std.testing.allocator.free(b);

    try std.testing.expectEqualSlices(u8, a, b);
}

test "structs" {
    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.dup(),
        Instruction.dup(),
        Instruction.push(42),
        Instruction.structStore(0),
        Instruction.structLoad(0),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 42);

    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.dup(),
        Instruction.push(42),
        Instruction.structStore(0),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{"a"}), "{a: 42}", 0);

    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.dup(),
        Instruction.dup(),
        Instruction.push(42),
        Instruction.structStore(0),
        Instruction.push(43),
        Instruction.structStore(1),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{ "a", "b" }), "{a: 42, b: 43}", 0);

    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.dup(),
        Instruction.structAlloc(),
        Instruction.structStore(0),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{"a"}), "{a: {}}", 0);

    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.structAlloc(),
        Instruction.load(0),
        Instruction.push(1),
        Instruction.structStore(0),

        Instruction.load(1),
        Instruction.push(1),
        Instruction.structStore(0),

        Instruction.load(0),
        Instruction.load(1),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{"a"}), "", 1);
    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.load(0),
        Instruction.load(0),
        Instruction.structStore(0),
        Instruction.load(0),
        Instruction.load(0),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{"a"}), "", 1);
    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.structAlloc(),

        Instruction.load(0),
        Instruction.load(1),
        Instruction.structStore(1), // a[b] = b
        Instruction.load(1),
        Instruction.load(0),
        Instruction.structStore(0), // b[a] = a

        Instruction.load(0),
        Instruction.dup(),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{ "a", "b" }), "", 1);

    try testRun(Program.init(&.{
        Instruction.structAlloc(),
        Instruction.structAlloc(),

        Instruction.load(0),
        Instruction.push(0),
        Instruction.structStore(1),
        Instruction.load(1),
        Instruction.push(1),
        Instruction.structStore(0),

        Instruction.load(0),
        Instruction.load(1),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{ "a", "b" }), "", 0);
}

test "lists" {
    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.dup(),
        Instruction.push(0),
        Instruction.push(42),
        Instruction.listStore(),
        Instruction.dup(),
        Instruction.push(0),
        Instruction.listLoad(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 42);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.dup(),
        Instruction.push(0),
        Instruction.push(42),
        Instruction.listStore(),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "[42]", 0);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),

        Instruction.dup(),
        Instruction.push(0),
        Instruction.push(42),
        Instruction.listStore(),

        Instruction.dup(),
        Instruction.push(1),
        Instruction.push(43),
        Instruction.listStore(),

        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "[42, 43]", 0);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.dup(),
        Instruction.push(0),
        Instruction.listAlloc(),
        Instruction.listStore(),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "[[]]", 0);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(0),
        Instruction.push(1),
        Instruction.listStore(),

        Instruction.load(1),
        Instruction.push(0),
        Instruction.push(1),
        Instruction.listStore(),

        Instruction.load(0),
        Instruction.load(1),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.load(0),
        Instruction.push(0),
        Instruction.load(0),
        Instruction.listStore(),
        Instruction.load(0),
        Instruction.load(0),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(0),
        Instruction.load(1),
        Instruction.listStore(), // list0[0] = list1
        Instruction.load(1),
        Instruction.push(0),
        Instruction.load(0),
        Instruction.listStore(), // list1[0] = list2

        Instruction.load(0),
        Instruction.dup(),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(0),
        Instruction.push(0),
        Instruction.listStore(),

        Instruction.load(1),
        Instruction.push(0),
        Instruction.push(1),
        Instruction.listStore(),

        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 0);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(0),
        Instruction.push(42),
        Instruction.listStore(),

        Instruction.load(1),
        Instruction.push(42),
        Instruction.listAppend(),

        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.dup(),
        Instruction.dup(),
        Instruction.dup(),
        Instruction.push(40),
        Instruction.listAppend(),
        Instruction.push(41),
        Instruction.listAppend(),
        Instruction.push(42),
        Instruction.listAppend(),

        Instruction.listLength(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 3);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(42),
        Instruction.listAppend(),

        Instruction.load(0),
        Instruction.listPop(),

        Instruction.push(42),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.listAlloc(),
        Instruction.listAlloc(),
        Instruction.listAlloc(),

        Instruction.load(0),
        Instruction.push(42),
        Instruction.listAppend(),

        Instruction.load(1),
        Instruction.push(43),
        Instruction.listAppend(),

        Instruction.load(2),
        Instruction.push(42),
        Instruction.listAppend(),

        Instruction.load(2),
        Instruction.push(43),
        Instruction.listAppend(),

        Instruction.load(0),
        Instruction.load(1),
        Instruction.listConcat(),

        Instruction.load(2),
        Instruction.equal(),

        Instruction.ret(),
    }, 0, &.{}, &.{}), "", 1);

    try testRun(
        Program.init(&.{
            Instruction.push(10),
            Instruction.push(1),
            Instruction.sub(),
            Instruction.dup(),
            Instruction.jmpnz(1),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        0,
    );

    // TODO: test list_remove
}

test "binary arithmetic operations" {
    const util = struct {
        fn testBinaryOp(op: Opcode) !void {
            for (0..100) |a| {
                for (1..100) |b| {
                    const lhs: i64 = @intCast(a);
                    const rhs: i64 = @intCast(b);

                    const res: i64 = if (op.isArithmetic() or op.isBitwise() or op.isLogical()) switch (op) {
                        .add => lhs + rhs,
                        .sub => lhs - rhs,
                        .mul => lhs * rhs,
                        .div => @intCast(a / b),
                        .mod => @intCast(a % b),
                        .bit_and => lhs & rhs,
                        .bit_or => lhs | rhs,
                        .bit_xor => lhs ^ rhs,
                        .log_or => @intFromBool(lhs != 0 or rhs != 0),
                        .log_and => @intFromBool(lhs != 0 and rhs != 0),
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
                            Instruction.ret(),
                        }, 0, &.{}, &.{}),
                        "",
                        res,
                    );

                    const lhsf: f64 = @floatFromInt(lhs);
                    const rhsf: f64 = @floatFromInt(rhs);

                    const resf: f64 = switch (op) {
                        .add => lhsf + rhsf,
                        .sub => lhsf - rhsf,
                        .mul => lhsf * rhsf,
                        .div => lhsf / rhsf,
                        else => continue,
                    };

                    try testRun(
                        Program.init(&.{
                            Instruction.pushf(lhsf),
                            Instruction.pushf(rhsf),
                            Instruction{ .op = op },
                            Instruction.pushf(resf),
                            Instruction.equal(),
                            Instruction.ret(),
                        }, 0, &.{}, &.{}),
                        "",
                        1,
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

    try util.testBinaryOp(.bit_and);
    try util.testBinaryOp(.bit_or);
    try util.testBinaryOp(.bit_xor);

    try util.testBinaryOp(.log_and);
    try util.testBinaryOp(.log_or);

    try util.testBinaryOp(.cmp_lt);
    try util.testBinaryOp(.cmp_gt);
    try util.testBinaryOp(.cmp_le);
    try util.testBinaryOp(.cmp_ge);
    try util.testBinaryOp(.cmp_eq);
    try util.testBinaryOp(.cmp_ne);

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

test "unary arithmetic operations" {
    try testRun(
        Program.init(&.{
            Instruction.push(0),
            Instruction.dup(),
            Instruction.pop(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        0,
    );

    try testRun(
        Program.init(&.{
            Instruction.push(10),
            Instruction.decrement(),
            Instruction.dup(),
            Instruction.jmpnz(1),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        0,
    );

    try testRun(
        Program.init(&.{
            Instruction.push(0),
            Instruction.increment(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        1,
    );

    try testRun(
        Program.init(&.{
            Instruction.push(0),
            Instruction.decrement(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        -1,
    );

    try testRun(
        Program.init(&.{
            Instruction.push(1),
            Instruction.negate(),
            Instruction.push(-1),
            Instruction.equal(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        1,
    );

    try testRun(
        Program.init(&.{
            Instruction.pushf(1.0),
            Instruction.negate(),
            Instruction.pushf(-1.0),
            Instruction.equal(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        1,
    );

    try testRun(
        Program.init(&.{
            Instruction.push(1),
            Instruction.bitwiseNot(),
            Instruction.push(-2),
            Instruction.equal(),
            Instruction.ret(),
        }, 0, &.{}, &.{}),
        "",
        1,
    );
}

test "fibonacci" {
    const prog = Program.init(&.{
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
        Instruction.ret(),
    }, 0, &.{}, &.{});
    try testRunWithJit(prog,
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
    , 0, .full);
}

test "recursive fibonacci" {
    const Asm = @import("asm").Asm;
    const DiagnosticList = @import("diagnostic").DiagnosticList;

    const source =
        \\-function $main
        \\-begin
        \\    push    %10             # push n
        \\    push    %1              # one arg
        \\    call    $fib            # call fib(n)
        \\    ret                     # return result
        \\-end
        \\
        \\-function $fib
        \\-begin
        \\    load    %-4             # load n
        \\    push    %2              # push 2
        \\    cmp_lt                  # n < 2 ?
        \\    jmpnz   .less_than_two  # if true skip next block
        \\
        \\    load    %-4             # load n
        \\    push    %1              # push 1
        \\    sub                     # n - 1
        \\    push    %1              # one arg
        \\    call    $fib            # fib(n - 1)
        \\    load    %-4             # load n
        \\    push    %2              # push 2
        \\    sub                     # n - 2
        \\    push    %1              # one arg
        \\    call    $fib            # fib(n - 2)
        \\    add                     # sum fib(n - 1) + fib(n - 2)
        \\    ret                     # return sum
        \\
        \\.less_than_two
        \\    load    %-4             # load n
        \\    ret                     # return n
        \\-end
    ;

    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();
    try assert(diagnostics.list.items.len == 0);

    var program = try asm_.getProgram(std.testing.allocator, .none);
    defer program.deinit();

    try testRunWithJit(program, "", 55, .full);
}

test "partial jit" {
    const Asm = @import("asm").Asm;
    const DiagnosticList = @import("diagnostic").DiagnosticList;

    {
        const source =
            \\-function $main
            \\-begin
            \\    push    %1
            \\    push    %2
            \\    push    %2
            \\    call    $test
            \\    ret
            \\-end
            \\
            \\-function $test
            \\-begin
            \\    load    %-5
            \\    load    %-4
            \\    cmp_lt
            \\    ret
            \\-end
        ;

        var diagnostics = DiagnosticList.init(std.testing.allocator, source);
        defer diagnostics.deinit();

        var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
        defer asm_.deinit();

        try asm_.assemble();
        try assert(diagnostics.list.items.len == 0);

        var program = try asm_.getProgram(std.testing.allocator, .none);
        defer program.deinit();

        try testRun(program, "", 1);
    }

    {
        const source =
            \\-function $main
            \\-begin
            \\    push    %1
            \\    push    %2
            \\    push    %2
            \\    call    $test
            \\    struct_alloc
            \\    pop
            \\    ret
            \\-end
            \\
            \\-function $test
            \\-begin
            \\    load    %-5
            \\    load    %-4
            \\    cmp_lt
            \\    ret
            \\-end
        ;

        var diagnostics = DiagnosticList.init(std.testing.allocator, source);
        defer diagnostics.deinit();

        var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
        defer asm_.deinit();

        try asm_.assemble();
        try assert(diagnostics.list.items.len == 0);

        var program = try asm_.getProgram(std.testing.allocator, .none);
        defer program.deinit();

        try testRunWithJit(program, "", 1, .partial);
    }
}

test "hello world" {
    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.syscall(0),
        Instruction.push(0),
        Instruction.ret(),
    }, 0, &.{"Hello World!"}, &.{}), "Hello World!", 0);
}

test "string compare" {
    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.equal(),
        Instruction.ret(),
    }, 0, &.{ "bar", "baz" }, &.{}), "", 0);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.lessEqual(),
        Instruction.ret(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.greaterEqual(),
        Instruction.ret(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.less(),
        Instruction.ret(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 0);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.greater(),
        Instruction.ret(),
    }, 0, &.{ "foo", "foo" }, &.{}), "", 0);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.less(),
        Instruction.ret(),
    }, 0, &.{ "a", "b" }, &.{}), "", 1);

    try testRun(Program.init(&.{
        Instruction.pushs(0),
        Instruction.pushs(1),
        Instruction.greater(),
        Instruction.ret(),
    }, 0, &.{ "a", "ab" }, &.{}), "", 0);
}
