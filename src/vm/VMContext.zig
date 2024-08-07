//!
//! VM execution context struct
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("arch");
const Instruction = arch.Instruction;
const Program = arch.Program;
const RtError = arch.err.RtError;
const Value = @import("memory_manager").APITypes.Value;
const Stack = std.ArrayList(Value);
const jit_mod = @import("jit");

const diagnostic = @import("diagnostic");
const Self = @This();

prog: Program,
pc: usize,
bp: usize = 0,
alloc: Allocator,
stack: Stack,
globals: []Value,
refc: i64 = 0,
write_buffer: *anyopaque,
write_buffer_destroy_fn: *const fn (self: *Self) void,
flush_fn: *const fn (write_buffer: *anyopaque) anyerror!void,
write_ctxt: *const anyopaque,
write_fn: *const fn (context: *anyopaque, bytes: []const u8) anyerror!usize,
stderr_write_ctxt: *const anyopaque,
stderr_write_fn: *const fn (context: *const anyopaque, bytes: []const u8) anyerror!usize,
debug_output: bool,
rterror: ?RtError = null,
jit_mode: JITMode = .auto,
jit_mask: std.DynamicBitSetUnmanaged,
jit_args: std.ArrayList(i64),
jit_fn: ?jit_mod.Function,
diagnostics: ?*diagnostic.DiagnosticList = null, // not owned by us, so we dont deinit it

pub const JITMode = enum { full, auto, off };

fn make_jit_mask(program: Program, alloc: Allocator) std.DynamicBitSetUnmanaged {
    var visited = std.DynamicBitSet.initEmpty(alloc, program.code.len) catch @panic("oom");
    defer visited.deinit();
    var jitable = std.DynamicBitSetUnmanaged.initEmpty(alloc, program.code.len) catch @panic("oom");

    const util = struct {
        fn dfs(prog: []const Instruction, i: usize, vis: *std.DynamicBitSet, jit: *std.DynamicBitSetUnmanaged) bool {
            if (i >= prog.len or vis.isSet(i) or jit.isSet(i)) {
                return true;
            }

            vis.set(i);

            return switch (prog[i].op) {
                // supported opcodes that dont branch
                .add,
                .sub,
                .mul,
                .mod,
                .div,
                .inc,
                .dec,
                .dup,
                .stack_alloc,
                .cmp_lt,
                .cmp_gt,
                .cmp_le,
                .cmp_ge,
                .cmp_eq,
                .cmp_ne,
                .syscall,
                .push,
                .pop,
                .load,
                .store,
                .glob_load,
                // TODO: Check if global values used by the function are
                // supported by the jit before calling compiled program.
                .glob_store,
                // go to next instruction
                => dfs(prog, i + 1, vis, jit),

                // branching
                .jmpnz, .call => dfs(prog, prog[i].operand.location, vis, jit) and dfs(prog, i + 1, vis, jit),

                .jmp => dfs(prog, prog[i].operand.location, vis, jit),

                // base case
                .ret => true,

                // unsupported instruction
                else => false,
            };
        }
    };

    if (program.fn_tbl) |fn_tbl| {
        for (fn_tbl.items) |sym| {
            visited.unmanaged.unsetAll();
            jitable.setValue(sym.addr, util.dfs(program.code, sym.addr, &visited, &jitable));
        }
    } else {
        jitable.setValue(program.entry, util.dfs(program.code, program.entry, &visited, &jitable));
    }

    return jitable;
}

pub fn init(prog: Program, alloc: Allocator, output_writer: anytype, error_writer: anytype, debug_output: bool) !Self {
    switch (@typeInfo(@TypeOf(output_writer))) {
        .Pointer => {},
        else => @compileError("output_writer has to be a pointer to a writer"),
    }
    switch (@typeInfo(@TypeOf(error_writer))) {
        .Pointer => {},
        else => @compileError("error_writer has to be a pointer to a writer"),
    }

    const tmp = std.io.bufferedWriter(output_writer.*);
    const BufType = @TypeOf(tmp);
    const write_buf = try alloc.create(@TypeOf(tmp));
    write_buf.* = tmp;

    const flush_fn = struct {
        fn flush(write_buffer: *anyopaque) !void {
            const buf: *BufType = @ptrCast(@alignCast(write_buffer));
            try buf.flush();
        }
    }.flush;

    const write_buffer_destroy_fn = struct {
        fn destroy_write_buffer(self: *Self) void {
            const buf: *BufType = @ptrCast(@alignCast(self.write_buffer));
            self.alloc.destroy(buf);
        }
    }.destroy_write_buffer;

    const write_fn = struct {
        fn write(write_buffer: *anyopaque, data: []const u8) anyerror!usize {
            const buf: *BufType = @ptrCast(@alignCast(write_buffer));
            return buf.write(data);
        }
    }.write;

    const stderr_write_fn = struct {
        fn write(write_ctxt: *const anyopaque, data: []const u8) anyerror!usize {
            return @as(@TypeOf(error_writer), @ptrCast(@alignCast(write_ctxt))).write(data);
        }
    }.write;

    return .{
        .prog = prog,
        .pc = prog.entry,
        .stack = Stack.init(alloc),
        .globals = try alloc.alloc(Value, prog.num_globs),
        .alloc = alloc,
        .write_buffer = write_buf,
        .write_buffer_destroy_fn = write_buffer_destroy_fn,
        .flush_fn = flush_fn,
        .write_ctxt = output_writer,
        .write_fn = write_fn,
        .stderr_write_ctxt = error_writer,
        .stderr_write_fn = stderr_write_fn,
        .debug_output = debug_output,
        .jit_mask = make_jit_mask(prog, alloc),
        .jit_args = std.ArrayList(i64).init(alloc),
        .jit_fn = null,
    };
}

pub fn flush(self: *Self) !void {
    try self.flush_fn(self.write_buffer);
}

pub fn reset(self: *Self) void {
    self.flush() catch @panic("flush failed when resetting VMContext");
    self.pc = self.prog.entry;
    self.bp = 0;
    for (self.stack.items) |_| {
        self.refc -= 1;
    }
    self.stack.clearAndFree();
}

pub fn write(self: *const Self, bytes: []const u8) anyerror!usize {
    return self.write_fn(self.write_buffer, bytes);
}

pub fn writeStderr(self: *const Self, bytes: []const u8) anyerror!usize {
    return self.stderr_write_fn(self.stderr_write_ctxt, bytes);
}

pub fn writer(self: *const Self) std.io.Writer(*const Self, anyerror, write) {
    return .{ .context = self };
}

pub fn errWriter(self: *const Self) std.io.Writer(*const Self, anyerror, writeStderr) {
    return .{ .context = self };
}

pub fn runtimeError(self: *Self, err_spec: arch.err.ErrorSpecifier) @TypeOf(error.RuntimeError) {
    self.rterror = .{
        .pc = self.pc - 1,
        .err = err_spec,
    };
    return error.RuntimeError;
}

pub fn deinit(self: *Self) void {
    self.flush() catch @panic("flush failed");
    self.write_buffer_destroy_fn(self);
    self.stack.deinit();
    self.jit_mask.deinit(self.alloc);
    if (self.jit_fn) |*jit_fn| {
        jit_fn.deinit();
    }
    self.jit_args.deinit();
    self.alloc.free(self.globals);
}
