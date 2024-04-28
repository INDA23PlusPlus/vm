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
debug_output: bool,

pub fn init(prog: Program, alloc: Allocator, output_writer: anytype, error_writer: anytype, debug_output: bool) Self {
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
            return @as(@TypeOf(output_writer), @ptrCast(@alignCast(write_ctxt))).write(data);
        }
    }.write;

    return .{
        .prog = prog,
        .pc = prog.entry,
        .bp = 0,
        .stack = Stack.init(alloc),
        .alloc = alloc,
        .refc = 0,
        .write_ctxt = output_writer,
        .write_fn = write_fn,
        .stderr_write_ctxt = output_writer,
        .stderr_write_fn = stderr_write_fn,
        .debug_output = debug_output,
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

pub fn writer(self: *const Self) std.io.Writer(*const Self, anyerror, write) {
    return .{ .context = self };
}

pub fn deinit(self: *Self) void {
    self.stack.deinit();
}
