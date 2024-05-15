const std = @import("std");
const arch = @import("arch");

const Self = @This();

err: ?anyerror = null,
unwind_sp: u64 = undefined,
err_pc: usize = undefined,
rterror: ?arch.err.RtError = null,
old_sigfpe_handler: std.os.linux.Sigaction = undefined,

write_ctxt: *const anyopaque = undefined,
write_fn: *const fn (*const anyopaque, []const u8) anyerror!usize = &default_write,

syscall_tbl: [2]*const anyopaque = .{
    &syscall_0,
    &syscall_1,
},

pub fn init() Self {
    var self = Self{};

    _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &.{ .handler = .{ .sigaction = &sigfpe_handler }, .mask = .{0} ** 32, .flags = std.os.linux.SA.SIGINFO }, &self.old_sigfpe_handler);

    return self;
}

pub fn deinit(self: *Self) void {
    _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &self.old_sigfpe_handler, null);
}

fn default_write(write_ctxt: *const anyopaque, bytes: []const u8) anyerror!usize {
    _ = write_ctxt;

    const output_stream = std.io.getStdOut();
    const output_writer = output_stream.writer();

    return output_writer.write(bytes);
}

fn write(self: *const Self, bytes: []const u8) anyerror!usize {
    return self.write_fn(self.write_ctxt, bytes);
}

inline fn writer(self: *const Self) std.io.Writer(*const Self, anyerror, write) {
    return .{ .context = self };
}

fn unwind() callconv(.Naked) noreturn {
    asm volatile (
        \\mov %[unwind_sp:c](%r15), %rsp
        \\pop %rbp
        \\pop %rcx
        \\lea (%rsp, %rcx, 8), %rsp
        \\pop %r15
        \\ret
        :
        : [unwind_sp] "i" (@offsetOf(Self, "unwind_sp")),
    );
}

fn sigfpe_handler(sig: i32, info: *const std.os.linux.siginfo_t, ucontext: ?*anyopaque) callconv(.C) void {
    _ = sig;
    _ = info;

    const uc: *std.os.linux.ucontext_t = @alignCast(@ptrCast(ucontext));
    const self: *Self = @ptrFromInt(uc.mcontext.gregs[std.os.linux.REG.R15]);

    self.err = error.RuntimeError;
    self.rterror = .{ .pc = null, .err = .division_by_zero };
    self.err_pc = uc.mcontext.gregs[std.os.linux.REG.RIP];

    uc.mcontext.gregs[std.os.linux.REG.RIP] = @intFromPtr(&unwind);
}

fn syscall_0(self: *Self, v: i64) callconv(.C) void {
    self.writer().print("{}\n", .{v}) catch {};
}

fn syscall_1(self: *Self, v: i64) callconv(.C) void {
    self.writer().print("{}", .{v}) catch {};
}
