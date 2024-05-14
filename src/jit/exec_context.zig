const std = @import("std");
const arch = @import("arch");

pub const ExecContext = extern struct {
    const Self = @This();

    pub const Common = struct {
        err: ?anyerror = null,

        write_ctxt: *const anyopaque = undefined,
        write_fn: *const fn (*const anyopaque, []const u8) anyerror!usize = &default_write,

        rterror: ?arch.err.RtError = null,

        fn default_write(write_ctxt: *const anyopaque, bytes: []const u8) anyerror!usize {
            _ = write_ctxt;

            const output_stream = std.io.getStdOut();
            const output_writer = output_stream.writer();

            return output_writer.write(bytes);
        }

        fn write(self: *const Common, bytes: []const u8) anyerror!usize {
            return self.write_fn(self.write_ctxt, bytes);
        }

        pub fn writer(self: *const Common) std.io.Writer(*const Common, anyerror, write) {
            return .{ .context = self };
        }
    };

    unwind_sp: u64 = undefined,

    syscall_tbl: [1]*const anyopaque = .{&syscall_0},

    err_pc: usize = undefined,

    old_sigfpe_handler: std.os.linux.Sigaction = undefined,

    common: *Common = undefined,

    fn unwind() callconv(.Naked) noreturn {
        asm volatile (
            \\mov (%r15), %rsp    # ExecContext.unwind_sp
            \\pop %rbp
            \\pop %rcx
            \\lea (%rsp, %rcx, 8), %rsp
            \\pop %r15
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
        exec_ctxt.common.writer().print("{}\n", .{v}) catch {};
    }

    pub fn init(common: *Common) Self {
        var self = Self{};

        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &.{ .handler = .{ .sigaction = &sigfpe_handler }, .mask = .{0} ** 32, .flags = std.os.linux.SA.SIGINFO }, &self.old_sigfpe_handler);

        self.common = common;

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &self.old_sigfpe_handler, null);
    }
};
