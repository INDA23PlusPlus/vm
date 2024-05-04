const std = @import("std");
const arch = @import("arch");
const as_lib = @import("as.zig");

const Self = @This();

const InsnMeta = struct {
    offset: usize,
    edge: bool,
};

const Reloc = struct {
    off: usize,
    val: union(enum) {
        off: usize,
        loc: usize,
    },
};

const Lbl = struct {
    ref: usize,
};

alloc: std.mem.Allocator,
as: as_lib.As,
insn_meta: std.ArrayList(InsnMeta),
relocs: std.ArrayList(Reloc),
dbgjit: ?[]const u8,

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
        .as = as_lib.As.init(alloc),
        .insn_meta = std.ArrayList(InsnMeta).init(alloc),
        .relocs = std.ArrayList(Reloc).init(alloc),
        .dbgjit = std.posix.getenv("DBGJIT"),
    };
}

pub fn deinit(self: *Self) void {
    self.as.deinit();
    self.insn_meta.deinit();
    self.relocs.deinit();
}

inline fn imm_size(imm: i64) usize {
    if (imm < std.math.minInt(i32) or imm > std.math.maxInt(i32)) {
        return 8;
    } else if (imm < std.math.minInt(i16) or imm > std.math.maxInt(i16)) {
        return 4;
    } else if (imm < std.math.minInt(i8) or imm > std.math.maxInt(i8)) {
        return 2;
    } else if (imm != 0) {
        return 1;
    } else {
        return 0;
    }
}

inline fn relocate(self: *Self, reloc: Reloc) void {
    const code = self.as.code();

    const val = switch (reloc.val) {
        .off => |off| off,
        .loc => |loc| self.insn_meta.items[loc].offset,
    };
    const off = val -% (reloc.off + 4);

    code[reloc.off + 0] = @truncate(off >> 0);
    code[reloc.off + 1] = @truncate(off >> 8);
    code[reloc.off + 2] = @truncate(off >> 16);
    code[reloc.off + 3] = @truncate(off >> 24);
}

inline fn relocate_all(self: *Self) void {
    for (self.relocs.items) |reloc| {
        self.relocate(reloc);
    }
}

inline fn call_loc(self: *Self, loc: usize) !void {
    try self.as.call_rel32(0);
    try self.relocs.append(.{ .off = self.as.imm_off, .val = .{ .loc = loc } });
}

inline fn jmp_loc(self: *Self, loc: usize) !void {
    try self.as.jmp_rel32(0);
    try self.relocs.append(.{ .off = self.as.imm_off, .val = .{ .loc = loc } });
}

inline fn jmp_lbl(self: *Self) !Lbl {
    try self.as.jmp_rel32(0);
    return .{ .ref = self.as.imm_off };
}

inline fn jcc_loc(self: *Self, cc: as_lib.CC, loc: usize) !void {
    try self.as.jcc_rel32(cc, 0);
    try self.relocs.append(.{ .off = self.as.imm_off, .val = .{ .loc = loc } });
}

inline fn jcc_lbl(self: *Self, cc: as_lib.CC) !Lbl {
    try self.as.jcc_rel32(cc, 0);
    return .{ .ref = self.as.imm_off };
}

inline fn put_lbl(self: *Self, lbl: Lbl) void {
    self.relocate(.{ .off = lbl.ref, .val = .{ .off = self.as.offset() } });
}

inline fn dbg_break(self: *Self, tag: ?[]const u8) !void {
    if (self.dbgjit) |v| {
        if (tag) |t| {
            var it = std.mem.split(u8, v, ",");
            while (it.next()) |s| {
                if (std.mem.eql(u8, s, t) or std.mem.eql(u8, s, "all")) {
                    try self.as.int3();
                    break;
                }
            }
        } else {
            try self.as.int3();
        }
    }
}

const exec_globals = struct {
    var exec_args: extern struct {
        unwind_sp: u64,
    } = undefined;

    var err: ?anyerror = undefined;

    var output_stream: std.fs.File = undefined;
    var output_writer: std.fs.File.Writer = undefined;

    var old_sigfpe_handler: std.os.linux.Sigaction = undefined;

    fn unwind() callconv(.Naked) noreturn {
        asm volatile (
            \\pop %rbp
            \\pop %rbx
            \\ret
            :
            : [unwind_sp] "{rsp}" (exec_args.unwind_sp),
        );
    }

    fn sigfpe_handler(sig: i32, info: *const std.os.linux.siginfo_t, ucontext: ?*anyopaque) callconv(.C) void {
        _ = sig;
        _ = info;

        err = error.InvalidOperation;

        const uc: *std.os.linux.ucontext_t = @alignCast(@ptrCast(ucontext));
        uc.mcontext.gregs[std.os.linux.REG.RIP] = @intFromPtr(&unwind);
    }

    inline fn init() void {
        err = null;

        output_stream = std.io.getStdOut();
        output_writer = output_stream.writer();

        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &.{ .handler = .{ .sigaction = &sigfpe_handler }, .mask = .{0} ** 32, .flags = std.os.linux.SA.SIGINFO }, &old_sigfpe_handler);
    }

    inline fn deinit() void {
        _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &old_sigfpe_handler, null);
    }
};

fn syscall_0(v: i64) callconv(.C) void {
    exec_globals.output_writer.print("{}\n", .{v}) catch {};
}

const VStack = struct {
    const Value = union(enum) {
        unit: void,
        sprel: i32,
        bprel: i32,
        reg: as_lib.R64,
        imm: i64,
        cc: as_lib.CC,
    };

    stack: std.ArrayList(Value),

    pub fn init(alloc: std.mem.Allocator) VStack {
        return .{ .stack = std.ArrayList(Value).init(alloc) };
    }

    pub fn deinit(self: *VStack) void {
        self.stack.deinit();
    }

    pub fn push(self: *VStack, value: Value) !void {
        try self.stack.append(value);
    }

    pub fn pop(self: *VStack) ?Value {
        if (self.stack.items.len != 0) {
            return self.stack.pop();
        } else {
            return null;
        }
    }

    pub fn get(self: *const VStack, offset: i64) ?Value {
        const n = @as(i64, @intCast(self.stack.items.len)) + offset - 1;

        if (n >= 0 and n < self.stack.items.len) {
            return self.stack.items[@as(usize, @intCast(n))];
        } else {
            return null;
        }
    }

    pub fn sync(self: *VStack, offset: i64, as: *as_lib.As) !void {
        var units: i32 = 0;

        while (@as(i64, @intCast(self.stack.items.len)) + offset > 0) {
            const v = self.stack.orderedRemove(0);

            if (v == .unit) {
                units += 1;
            } else {
                if (units != 0) {
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
                    units = 0;
                }
                switch (v) {
                    .unit => unreachable,
                    .sprel => |sprel| {
                        try as.push_rm64(.{ .mem = .{ .base = .RSP, .disp = sprel } });
                    },
                    .bprel => |bprel| {
                        try as.push_rm64(.{ .mem = .{ .base = .RBP, .disp = bprel } });
                    },
                    .reg => |reg| {
                        try as.push_r64(reg);
                    },
                    .imm => |imm| {
                        if (imm_size(imm) > 4) {
                            try as.mov_r64_imm64(.RSI, imm);
                            try as.push_r64(.RSI);
                        } else {
                            try as.push_imm32(@intCast(imm));
                        }
                    },
                    .cc => |cc| {
                        try as.setcc_rm8(cc, .{ .reg = .CL });
                        try as.movzx_r64_rm8(.RCX, .{ .reg = .CL });
                        try as.push_r64(.RCX);
                    },
                }
            }
        }

        if (units != 0) {
            try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
        }
    }

    pub fn clobber_reg(self: *VStack, reg: as_lib.R64, as: *as_lib.As) !void {
        const b = 1 - @as(i64, @intCast(self.stack.items.len));

        for (0..self.stack.items.len) |i| {
            const j = self.stack.items.len - 1 - i;
            const v = self.stack.items[j];
            if (v == .reg and v.reg == reg) {
                return self.sync(b + @as(i64, @intCast(j)), as);
            }
        }
    }

    pub fn clobber_cc(self: *VStack, as: *as_lib.As) !void {
        const b = 1 - @as(i64, @intCast(self.stack.items.len));

        for (0.., self.stack.items) |i, v| {
            if (v == .cc) {
                return self.sync(b + @as(i64, @intCast(i)), as);
            }
        }
    }
};

fn opcode_cc(opcode: arch.Opcode) as_lib.CC {
    return switch (opcode) {
        .cmp_lt => as_lib.CC.L,
        .cmp_gt => as_lib.CC.G,
        .cmp_eq => as_lib.CC.E,
        .cmp_ne => as_lib.CC.NE,
        else => unreachable,
    };
}

pub fn compile(self: *Self, prog: arch.Program) !void {
    const as = &self.as;

    try self.insn_meta.appendNTimes(.{ .offset = undefined, .edge = false }, prog.code.len);

    for (0.., prog.code) |i, insn| {
        switch (insn.op) {
            .call, .syscall => {
                self.insn_meta.items[i].edge = true;
            },
            .ret => {
                // Handled manually in code generator
            },
            .jmp => {
                self.insn_meta.items[i].edge = true;
                self.insn_meta.items[insn.operand.location].edge = true;
            },
            .jmpnz => {
                // Outgoing edge handled manually in code generator
                self.insn_meta.items[insn.operand.location].edge = true;
            },
            else => {},
        }
    }

    var vstk = VStack.init(self.alloc);
    defer vstk.deinit();

    try self.dbg_break("start");
    try as.push_r64(.RBX);
    try as.push_r64(.RBP);
    try as.mov_rm64_r64(.{ .mem = .{ .base = .RDI } }, .RSP);
    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
    try self.call_loc(prog.entry);
    try self.dbg_break("end");
    try as.pop_r64(.RBP);
    try as.pop_r64(.RBX);
    try as.ret_near();

    for (0.., prog.code) |i, insn| {
        if (self.insn_meta.items[i].edge) {
            try vstk.sync(0, as);
        }

        switch (insn.op) {
            .add => {
                try vstk.sync(0, as);
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("add");
                try as.pop_r64(.RCX);
                try as.add_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .sub => {
                try vstk.sync(0, as);
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("sub");
                try as.pop_r64(.RCX);
                try as.sub_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .mul => {
                if (vstk.pop()) |b| {
                    if (vstk.pop()) |a| {
                        try vstk.clobber_reg(.RAX, as);
                        try vstk.clobber_reg(.RDX, as);
                        try vstk.clobber_cc(as);
                        switch (a) {
                            .sprel => |sprel_a| {
                                switch (b) {
                                    .sprel => |sprel_b| {
                                        try vstk.sync(0, as);
                                        self.insn_meta.items[i].offset = as.offset();
                                        try self.dbg_break("mul");
                                        try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RSP, .disp = sprel_a } });
                                        try as.imul_rm64(.{ .mem = .{ .base = .RSP, .disp = sprel_b - 8 } });
                                        try vstk.push(.{ .reg = .RAX });
                                    },
                                    else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                                }
                            },
                            .bprel => |bprel_a| {
                                switch (b) {
                                    .bprel => |bprel_b| {
                                        self.insn_meta.items[i].offset = as.offset();
                                        try self.dbg_break("mul");
                                        try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = bprel_a } });
                                        try as.imul_rm64(.{ .mem = .{ .base = .RBP, .disp = bprel_b } });
                                        try vstk.push(.{ .reg = .RAX });
                                    },
                                    else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                                }
                            },
                            else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                        }
                    } else {
                        // vstk empty, no need to sync
                        switch (b) {
                            .sprel => |sprel_b| {
                                try vstk.sync(0, as);
                                self.insn_meta.items[i].offset = as.offset();
                                try self.dbg_break("mul");
                                try as.pop_r64(.RAX);
                                try as.imul_rm64(.{ .mem = .{ .base = .RSP, .disp = sprel_b - 8 } });
                                try vstk.push(.{ .reg = .RAX });
                            },
                            else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: .. {s}.", .{ i, @tagName(insn.op), @tagName(b) }),
                        }
                    }
                }
                else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("mul");
                    try as.pop_r64(.RAX);
                    try as.imul_rm64(.{ .mem = .{ .base = .RSP } });
                    try vstk.push(.{ .reg = .RAX });
                }
            },
            .mod => {
                if (vstk.pop()) |b| {
                    if (vstk.pop()) |a| {
                        try vstk.clobber_reg(.RAX, as);
                        try vstk.clobber_reg(.RDX, as);
                        try vstk.clobber_cc(as);
                        self.insn_meta.items[i].offset = as.offset();
                        try self.dbg_break("mod");
                        switch (a) {
                            .bprel => |bprel| {
                                try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = bprel } });
                            },
                            .reg => |reg| {
                                if (reg != .RAX) {
                                    try as.mov_rm64_r64(.{ .reg = .RAX }, reg);
                                }
                            },
                            else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                        }
                    } else {
                        // vstk empty, no need to sync
                        self.insn_meta.items[i].offset = as.offset();
                        try self.dbg_break("mod");
                        try as.pop_r64(.RAX);
                    }
                    try as.cqo();
                    switch (b) {
                        .bprel => |bprel| {
                            try as.idiv_rm64(.{ .mem = .{ .base = .RBP, .disp = bprel } });
                        },
                        .reg => |reg| {
                            try as.idiv_rm64(.{ .reg = reg });
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: .. {s}.", .{ i, @tagName(insn.op), @tagName(b) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("mod");
                    try as.pop_r64(.RCX);
                    try as.pop_r64(.RAX);
                    try as.cqo();
                    try as.idiv_rm64(.{ .reg = .RCX });
                }
                try vstk.push(.{ .reg = .RDX });
            },
            .inc => {
                if (vstk.pop()) |v| {
                    try vstk.clobber_reg(.RAX, as);
                    try vstk.clobber_cc(as);
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("inc");
                    switch (v) {
                        .bprel => |bprel| {
                            try as.inc_rm64(.{ .mem = .{ .base = .RBP, .disp = bprel } });
                        },
                        .imm => |imm| {
                            try vstk.push(.{ .imm = imm - 1 });
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("inc");
                    try as.inc_rm64(.{ .mem = .{ .base = .RSP } });
                }
            },
            .dec => {
                if (vstk.pop()) |v| {
                    try vstk.clobber_reg(.RAX, as);
                    try vstk.clobber_cc(as);
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("dec");
                    switch (v) {
                        .bprel => |bprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = bprel } });
                            try as.dec_rm64(.{ .reg = .RAX });
                            try vstk.push(.{ .reg = .RAX });
                        },
                        .imm => |imm| {
                            try vstk.push(.{ .imm = imm - 1 });
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("dec");
                    try as.dec_rm64(.{ .mem = .{ .base = .RSP } });
                }
            },
            .dup => {
                if (vstk.get(0)) |v| {
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("dup");
                    if (v == .sprel) {
                        try vstk.push(.{ .sprel = v.sprel + 8 });
                    } else {
                        try vstk.push(v);
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("dup");
                    try vstk.push(.{ .sprel = 0 });
                }
            },
            .stack_alloc => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("stack_alloc");
                for (0..@as(usize, @intCast(insn.operand.int))) |_| {
                    try vstk.push(.{ .unit = void{} });
                }
            },
            inline .cmp_lt, .cmp_gt, .cmp_eq, .cmp_ne => |cmp| {
                if (vstk.pop()) |b| {
                    if (vstk.pop()) |a| {
                        try vstk.clobber_cc(as);
                        self.insn_meta.items[i].offset = as.offset();
                        try self.dbg_break(@tagName(cmp));
                        switch (a) {
                            .bprel => |bprel_a| {
                                switch (b) {
                                    .reg => |reg_b| {
                                        try as.cmp_rm64_r64(.{ .mem = .{ .base = .RBP, .disp = bprel_a } }, reg_b);
                                    },
                                    .imm => |imm_b| {
                                        if (imm_size(imm_b) > 4) {
                                            try as.mov_r64_imm64(.RBX, imm_b);
                                            try as.cmp_rm64_r64(.{ .mem = .{ .base = .RBP, .disp = bprel_a } }, .RBX);
                                        } else {
                                            try as.cmp_rm64_imm32(.{ .mem = .{ .base = .RBP, .disp = bprel_a } }, @intCast(imm_b));
                                        }
                                    },
                                    else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                                }
                            },
                            .reg => |reg_a| {
                                switch (b) {
                                    .bprel => |bprel| {
                                        try as.cmp_r64_rm64(reg_a, .{ .mem = .{ .base = .RBP, .disp = bprel } });
                                    },
                                    .reg => |reg_b| {
                                        try as.cmp_rm64_r64(.{ .reg = reg_a }, reg_b);
                                    },
                                    .imm => |imm_b| {
                                        if (imm_size(imm_b) > 4) {
                                            try as.mov_r64_imm64(.RBX, imm_b);
                                            try as.cmp_rm64_r64(.{ .reg = reg_a }, .RBX);
                                        } else {
                                            try as.cmp_rm64_imm32(.{ .reg = reg_a }, @intCast(imm_b));
                                        }
                                    },
                                    else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s} {s}.", .{ i, @tagName(insn.op), @tagName(a), @tagName(b) }),
                                }
                            },
                            else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(a) }),
                        }
                    } else {
                        // vstk empty, no need to sync
                        self.insn_meta.items[i].offset = as.offset();
                        try self.dbg_break(@tagName(cmp));
                        try as.pop_r64(.RCX);
                        switch (b) {
                            .bprel => |bprel| {
                                try as.cmp_r64_rm64(.RCX, .{ .mem = .{ .base = .RBP, .disp = bprel } });
                            },
                            .reg => |reg| {
                                try as.cmp_rm64_r64(.{ .reg = .RCX }, reg);
                            },
                            .imm => |imm| {
                                if (imm_size(imm) > 4) {
                                    try as.mov_r64_imm64(.RSI, imm);
                                    try as.cmp_rm64_r64(.{ .reg = .RCX }, .RSI);
                                } else {
                                    try as.cmp_rm64_imm32(.{ .reg = .RCX }, @intCast(imm));
                                }
                            },
                            else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: .. {s}.", .{ i, @tagName(insn.op), @tagName(b) }),
                        }
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break(@tagName(cmp));
                    try as.pop_r64(.RSI);
                    try as.pop_r64(.RCX);
                    try as.cmp_rm64_r64(.{ .reg = .RCX }, .RSI);
                }
                try vstk.push(.{ .cc = opcode_cc(cmp) });
            },
            .call => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("call");
                try as.push_r64(.RBP);
                try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
                try self.call_loc(insn.operand.location);
                try self.dbg_break("call_ret");
                try as.pop_r64(.RBP);
                try as.pop_r64(.RCX);
                try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });
                try vstk.push(.{ .reg = .RAX });
            },
            .syscall => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("syscall");
                switch (insn.operand.int) {
                    0 => {
                        try as.mov_r64_rm64(.RDI, .{ .mem = .{ .base = .RSP } });
                        try as.mov_r64_imm64(.RAX, @bitCast(@intFromPtr(&syscall_0)));
                        try as.test_rm64_imm32(.{ .reg = .RSP }, 8);
                        const la = try self.jcc_lbl(.NE);
                        try as.call_rm64(.{ .reg = .RAX });
                        try as.add_rm64_imm8(.{ .reg = .RSP }, 8);
                        try self.dbg_break("syscall_ret");
                        const lb = try self.jmp_lbl();
                        self.put_lbl(la);
                        try as.add_rm64_imm8(.{ .reg = .RSP }, 8);
                        try as.call_rm64(.{ .reg = .RAX });
                        try self.dbg_break("syscall_ret");
                        self.put_lbl(lb);
                    },
                    else => {},
                }
            },
            .ret => {
                if (vstk.pop()) |v| {
                    // stack is being cleared, no need to sync vstk
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("ret");
                    switch (v) {
                        .bprel => |bprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = bprel } });
                        },
                        .reg => |reg| {
                            if (reg != .RAX) {
                                try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                            }
                        },
                        .imm => |imm| {
                            try as.mov_r64_imm64(.RAX, imm);
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("ret");
                    try as.pop_r64(.RAX);
                }
                try as.mov_r64_rm64(.RSP, .{ .reg = .RBP });
                try as.ret_near();
            },
            .jmp => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("jmp");
                try self.jmp_loc(insn.operand.location);
            },
            .jmpnz => {
                if (vstk.pop()) |v| {
                    try vstk.sync(0, as);
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("jmpnz");
                    switch (v) {
                        .reg => |reg| {
                            try as.test_rm64_r64(.{ .reg = reg }, reg);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .cc => |cc| {
                            try self.jcc_loc(cc, insn.operand.location);
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("jmpnz");
                    try as.pop_r64(.RCX);
                    try as.test_rm64_r64(.{ .reg = .RCX }, .RCX);
                    try self.jcc_loc(.NE, insn.operand.location);
                }
            },
            .push => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("push");
                try vstk.push(.{ .imm = insn.operand.int });
            },
            .pop => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("pop");
                if (vstk.pop()) |_| {} else {
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = 8 });
                }
            },
            .load => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("load");
                try vstk.push(.{ .bprel = @intCast((insn.operand.int + 1) * -8) });
            },
            .store => {
                const rm = as_lib.RM64{ .mem = .{ .base = .RBP, .disp = @truncate((-insn.operand.int - 1) * 8) } };
                if (vstk.pop()) |v| {
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("store");
                    switch (v) {
                        .imm => |imm| {
                            if (imm_size(imm) > 4) {
                                try as.mov_r64_imm64(.RCX, imm);
                                try as.mov_rm64_r64(rm, .RCX);
                            } else {
                                try as.mov_rm64_imm32(rm, @intCast(imm));
                            }
                        },
                        else => std.debug.panic("@{}: Unimplemented vstk condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // vstk empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("store");
                    try as.pop_r64(.RCX);
                    try as.mov_rm64_r64(rm, .RCX);
                }
            },
            else => {
                std.debug.panic("@{}: Unimplemented instruction: {s}.\n", .{ i, @tagName(insn.op) });
            },
        }
    }

    self.relocate_all();
}

pub fn execute(self: *Self) !i64 {
    const code = self.as.code();
    const size = self.as.offset();

    const addr = std.os.linux.mmap(null, size, std.os.linux.PROT.READ | std.os.linux.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr = @as(?[*]u8, @ptrFromInt(addr)) orelse return error.OutOfMemory;
    defer _ = std.os.linux.munmap(ptr, size);

    @memcpy(ptr, code);

    if (std.os.linux.mprotect(ptr, size, std.os.linux.PROT.READ | std.os.linux.PROT.EXEC) != 0) {
        return error.AccessDenied;
    }

    exec_globals.init();
    defer exec_globals.deinit();

    const fn_ptr: *fn (*anyopaque) callconv(.C) i64 = @ptrCast(ptr);
    const ret = fn_ptr(&exec_globals.exec_args);

    return exec_globals.err orelse ret;
}
