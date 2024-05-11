//!
//! VM execution context struct
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("arch");
const Instruction = arch.Instruction;
const Program = arch.Program;
const Type = @import("memory_manager").APITypes.Type;
const Stack = std.ArrayList(Type);
const RtError = @import("rterror.zig").RtError;

const Self = @This();

prog: Program,
pc: usize,
bp: usize,
alloc: Allocator,
stack: Stack,
refc: i64,
write_ctxt: *const anyopaque,
write_fn: *const fn (context: *const anyopaque, bytes: []const u8) anyerror!usize,
stderr_write_ctxt: *const anyopaque,
stderr_write_fn: *const fn (context: *const anyopaque, bytes: []const u8) anyerror!usize,
read_ctxt: *const anyopaque,
read_fn: *const fn (context: *const anyopaque, bytes: []u8) anyerror!usize,
debug_output: bool,
rterror: ?RtError = null,
jit_mask: std.DynamicBitSetUnmanaged,

fn make_jit_mask(program: Program, alloc: Allocator) std.DynamicBitSetUnmanaged {
    var visited = std.DynamicBitSet.initEmpty(alloc, program.code.len) catch @panic("oom");
    defer visited.deinit();
    var jitable = std.DynamicBitSetUnmanaged.initEmpty(alloc, program.code.len) catch @panic("oom");

    const util = struct {
        fn dfs(fn_start: usize, prog: []const Instruction, i: usize, vis: *std.DynamicBitSet, jit: *std.DynamicBitSetUnmanaged) bool {
            if (i >= prog.len) return true;
            if (vis.isSet(i)) return true;
            vis.set(i);

            return switch (prog[i].op) {
                // supported opcodes that dont branch
                .add,
                .sub,
                .mul,
                .mod,
                .inc,
                .dec,
                .dup,
                .stack_alloc,
                .cmp_lt,
                .cmp_gt,
                .cmp_eq,
                .cmp_ne,
                .syscall,
                .push,
                .pop,
                .load,
                .store,
                // go to next instruction
                => dfs(fn_start, prog, i + 1, vis, jit),

                // branching
                .jmpnz => {
                    const dest = prog[i].operand.location;
                    const res = dfs(fn_start, prog, prog[i].operand.location, vis, jit) and dfs(fn_start, prog, i + 1, vis, jit);
                    jit.setValue(dest, res);
                    return res;
                },

                // if we recurse or call another jittable function
                .jmp,
                .call,
                => {
                    const dest = prog[i].operand.location;
                    const res = prog[i].operand.location == fn_start or
                        dfs(prog[i].operand.location, prog, prog[i].operand.location, vis, jit);
                    jit.setValue(dest, res);
                    return res;
                },
                // base case
                .ret => true,

                // unsupported instruction
                else => false,
            };
        }
    };

    const main_jitable = util.dfs(program.entry, program.code, program.entry, &visited, &jitable);
    jitable.setValue(program.entry, main_jitable);
    return jitable;
}

pub fn init(prog: Program, alloc: Allocator, output_writer: anytype, error_writer: anytype, input_reader: anytype, debug_output: bool) Self {
    switch (@typeInfo(@TypeOf(output_writer))) {
        .Pointer => {},
        else => @compileError("output_writer has to be a pointer to a writer"),
    }
    switch (@typeInfo(@TypeOf(error_writer))) {
        .Pointer => {},
        else => @compileError("error_writer has to be a pointer to a writer"),
    }

    const write_fn = struct {
        fn write(write_ctxt: *const anyopaque, data: []const u8) anyerror!usize {
            return @as(@TypeOf(output_writer), @ptrCast(@alignCast(write_ctxt))).write(data);
        }
    }.write;

    const stderr_write_fn = struct {
        fn write(write_ctxt: *const anyopaque, data: []const u8) anyerror!usize {
            return @as(@TypeOf(error_writer), @ptrCast(@alignCast(write_ctxt))).write(data);
        }
    }.write;

    const read_fn = struct {
        fn read(read_ctxt: *const anyopaque, data: []u8) anyerror!usize {
            return @as(@TypeOf(input_reader), @ptrCast(@alignCast(read_ctxt))).read(data);
        }
    }.read;

    return .{
        .prog = prog,
        .pc = prog.entry,
        .bp = 0,
        .stack = Stack.init(alloc),
        .alloc = alloc,
        .refc = 0,
        .write_ctxt = output_writer,
        .write_fn = write_fn,
        .stderr_write_ctxt = error_writer,
        .stderr_write_fn = stderr_write_fn,
        .read_ctxt = input_reader,
        .read_fn = read_fn,
        .debug_output = debug_output,
        .jit_mask = make_jit_mask(prog, alloc),
    };
}

pub fn reset(self: *Self) void {
    self.pc = self.prog.entry;
    self.bp = 0;
    for (self.stack.items) |*v| {
        v.deinit();
        self.refc -= 1;
    }
    self.stack.clearAndFree();
}

pub fn write(self: *const Self, bytes: []const u8) anyerror!usize {
    return self.write_fn(self.write_ctxt, bytes);
}

pub fn writeStderr(self: *const Self, bytes: []const u8) anyerror!usize {
    return self.stderr_write_fn(self.stderr_write_ctxt, bytes);
}

pub fn read(self: *const Self, bytes: []u8) anyerror!usize {
    return self.read_fn(self.read_ctxt, bytes);
}

pub fn writer(self: *const Self) std.io.Writer(*const Self, anyerror, write) {
    return .{ .context = self };
}

pub fn errWriter(self: *const Self) std.io.Writer(*const Self, anyerror, writeStderr) {
    return .{ .context = self };
}

pub fn reader(self: *const Self) std.io.Reader(*const Self, anyerror, read) {
    return .{ .context = self };
}

pub fn deinit(self: *Self) void {
    self.stack.deinit();
    self.jit_mask.deinit(self.alloc);
}
