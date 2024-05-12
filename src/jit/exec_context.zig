const std = @import("std");
const arch = @import("arch");

pub const ExecContext = extern struct {
    const Self = @This();

    pub const Common = struct {
        err: ?anyerror = undefined,

        output_stream: std.fs.File = undefined,
        output_writer: std.fs.File.Writer = undefined,

        rterror: ?arch.err.RtError = undefined,
    };

    unwind_sp: u64 = undefined,

    syscall_tbl: [1]*const anyopaque = .{&syscall_0},

    err_pc: usize = undefined,

    old_sigfpe_handler: std.os.linux.Sigaction = undefined,

    common: *Common = undefined,

    fn unwind() callconv(.Naked) noreturn {
        asm volatile (
            \\mov (%r15), %rsp    # ExecContext.unwind_sp
            \\pop %r15
            \\pop %rbx
            \\pop %rbp
            \\ret
        );
    }

    fn sigfpe_handler(sig: i32, info: *const std.os.linux.siginfo_t, ucontext: ?*anyopaque) callconv(.C) void {
        _ = sig;
        _ = info;

        const uc: *std.os.linux.ucontext_t = @alignCast(@ptrCast(ucontext));
        const self: *Self = @ptrFromInt(uc.mcontext.gregs[std.os.linux.REG.R15]);

        self.common.err = error.RuntimeError;
        self.common.rterror = .{ .pc = null, .err = .division_by_zero };
        self.err_pc = uc.mcontext.gregs[std.os.linux.REG.RIP];

        uc.mcontext.gregs[std.os.linux.REG.RIP] = @intFromPtr(&unwind);
    }

    fn syscall_0(exec_ctxt: *ExecContext, v: i64) callconv(.C) void {
        exec_ctxt.common.output_writer.print("{}\n", .{v}) catch {};
    }

    pub fn init(common: *Common) Self {
        var self = Self{};

        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &.{ .handler = .{ .sigaction = &sigfpe_handler }, .mask = .{0} ** 32, .flags = std.os.linux.SA.SIGINFO }, &self.old_sigfpe_handler);

        common.err = null;
        common.rterror = null;

        common.output_stream = std.io.getStdOut();
        common.output_writer = common.output_stream.writer();

        self.common = common;

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &self.old_sigfpe_handler, null);
    }
};
