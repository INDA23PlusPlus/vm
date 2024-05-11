const std = @import("std");
const arch = @import("arch");
const as_lib = @import("as.zig");
const ExecContext = @import("exec_context.zig").ExecContext;
const Function = @import("Function.zig");

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

inline fn opcode_cc(opcode: arch.Opcode) as_lib.CC {
    return switch (opcode) {
        .cmp_lt => as_lib.CC.L,
        .cmp_gt => as_lib.CC.G,
        .cmp_le => as_lib.CC.LE,
        .cmp_ge => as_lib.CC.GE,
        .cmp_eq => as_lib.CC.E,
        .cmp_ne => as_lib.CC.NE,
        else => unreachable,
    };
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

const Context = struct {
    const VmdVal = union(enum) {
        unit,
        sprel: i32,
        bprel: i32,
        imm: i64,
        asm_reg: as_lib.R64,
        asm_cc: as_lib.CC,
    };

    const AsmVal = struct {
        val: union(enum) {
            top, // Top of the real stack
            mem: as_lib.Mem, // Memory address (RSP displacement subject to adjustment)
            reg: as_lib.R64, // Register
            imm: i64, // Immediate value
        },
        sp: i32 = undefined, // sp reference value for sp-relative memory addres
    };

    // Virtal stack of values not yet committed to the real stack
    vstk: std.ArrayList(VmdVal),

    // Reference value for the "real" sp, used to adjust sp-relative memory accesses
    sp: i32,

    pub fn init(alloc: std.mem.Allocator) Context {
        return .{ .vstk = std.ArrayList(VmdVal).init(alloc), .sp = 0 };
    }

    pub fn deinit(self: *Context) void {
        self.vstk.deinit();
    }

    pub fn vstk_push(self: *Context, value: VmdVal) !void {
        try self.vstk.append(value);
    }

    pub fn vstk_pop(self: *Context) ?VmdVal {
        if (self.vstk.items.len != 0) {
            return self.vstk.pop();
        } else {
            return null;
        }
    }

    pub fn vstk_get(self: *const Context, offset: i64) ?VmdVal {
        const n = @as(i64, @intCast(self.vstk.items.len)) + offset - 1;

        if (n >= 0 and n < self.vstk.items.len) {
            return self.vstk.items[@as(usize, @intCast(n))];
        } else {
            return null;
        }
    }

    pub fn vstk_sync(self: *Context, offset: i64, as: *as_lib.As) !void {
        var units: i32 = 0;

        while (@as(i64, @intCast(self.vstk.items.len)) + offset > 0) {
            const v = self.vstk.orderedRemove(0);

            if (v == .unit) {
                units += 1;
            } else {
                if (units != 0) {
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
                    self.sp += units;
                    units = 0;
                }
                switch (v) {
                    .unit => unreachable,
                    .sprel => |sprel| {
                        try as.push_rm64(.{ .mem = .{ .base = .RSP, .disp = -8 * (sprel + 1) } });
                    },
                    .bprel => |bprel| {
                        try as.push_rm64(.{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } });
                    },
                    .imm => |imm| {
                        if (imm_size(imm) > 4) {
                            try as.mov_r64_imm64(.RSI, imm);
                            try as.push_r64(.RSI);
                        } else {
                            try as.push_imm32(@intCast(imm));
                        }
                    },
                    .asm_reg => |reg| {
                        try as.push_r64(reg);
                    },
                    .asm_cc => |cc| {
                        try as.setcc_rm8(cc, .{ .reg = .CL });
                        try as.movzx_r64_rm8(.RCX, .{ .reg = .CL });
                        try as.push_r64(.RCX);
                    },
                }
                self.sp += 1;
            }
        }

        if (units != 0) {
            try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
            self.sp += units;
        }
    }

    pub fn vstk_full_sync(self: *Context, as: *as_lib.As) !void {
        try self.vstk_sync(0, as);
        self.sp = 0;
    }

    pub fn clobber_reg(self: *Context, reg: as_lib.R64, as: *as_lib.As) !void {
        const b = 1 - @as(i64, @intCast(self.vstk.items.len));

        for (0..self.vstk.items.len) |i| {
            const j = self.vstk.items.len - 1 - i;
            const v = self.vstk.items[j];
            if (v == .asm_reg and v.asm_reg == reg) {
                return self.vstk_sync(b + @as(i64, @intCast(j)), as);
            }
        }
    }

    pub fn clobber_cc(self: *Context, as: *as_lib.As) !void {
        const b = 1 - @as(i64, @intCast(self.vstk.items.len));

        for (0..self.vstk.items.len) |i| {
            const j = self.vstk.items.len - 1 - i;
            const v = self.vstk.items[j];
            if (v == .asm_cc) {
                return self.vstk_sync(b + @as(i64, @intCast(i)), as);
            }
        }
    }

    pub fn clobber_bprel(self: *Context, bprel: i32, as: *as_lib.As) !void {
        const b = 1 - @as(i64, @intCast(self.vstk.items.len));

        for (0..self.vstk.items.len) |i| {
            const j = self.vstk.items.len - 1 - i;
            const v = self.vstk.items[j];
            if (v == .bprel and v.bprel == bprel) {
                return self.vstk_sync(b + @as(i64, @intCast(i)), as);
            }
        }
    }

    pub fn vstk_pop_asm(self: *Context, as: *as_lib.As) !AsmVal {
        if (self.vstk_pop()) |v| {
            switch (v) {
                .unit => {
                    return .{ .val = .{ .imm = 0 } };
                },
                .sprel => |sprel| {
                    try self.vstk_sync(sprel + 1, as);
                    return .{ .val = .{ .mem = .{ .base = .RSP, .disp = -8 * (sprel + 1 + @as(i32, @intCast(self.vstk.items.len))) } }, .sp = self.sp };
                },
                .bprel => |bprel| {
                    return .{ .val = .{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } } };
                },
                .imm => |imm| {
                    return .{ .val = .{ .imm = imm } };
                },
                .asm_reg => |reg| {
                    return .{ .val = .{ .reg = reg } };
                },
                .asm_cc => unreachable,
            }
        } else {
            return .{ .val = .top };
        }
    }

    // Emit a pop instruction and adjust reference sp
    pub fn pop_r64(self: *Context, reg: as_lib.R64, as: *as_lib.As) !void {
        try as.pop_r64(reg);

        self.sp -= 1;
    }

    // Adjust the displacement of a memory asm val according to the reference sp
    pub fn asm_val_mem(self: *Context, v: AsmVal) as_lib.Mem {
        var mem = v.val.mem;

        if (mem.base == .RSP) {
            mem.disp -= (v.sp - self.sp) * 8;
        }

        return mem;
    }
};

fn syscall_0(exec_ctxt: *ExecContext, v: i64) callconv(.C) void {
    exec_ctxt.common.output_writer.print("{}\n", .{v}) catch {};
}

fn compile_slice(self: *Self, code: []const arch.Instruction) !void {
    const as = &self.as;

    var ctxt = Context.init(self.alloc);
    defer ctxt.deinit();

    try self.insn_meta.appendNTimes(.{ .offset = undefined, .edge = false }, code.len);

    for (code) |insn| {
        switch (insn.op) {
            .jmp, .jmpnz => {
                self.insn_meta.items[insn.operand.location].edge = true;
            },
            else => {},
        }
    }

    for (0.., code) |i, insn| {
        if (self.insn_meta.items[i].edge) {
            try ctxt.vstk_full_sync(as);
        }

        switch (insn.op) {
            .add => {
                try ctxt.vstk_full_sync(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("add");

                try as.pop_r64(.RCX);
                try as.add_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .sub => {
                try ctxt.vstk_full_sync(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("sub");

                try as.pop_r64(.RCX);
                try as.sub_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .mul => {
                const b = try ctxt.vstk_pop_asm(as);
                const a = try ctxt.vstk_pop_asm(as);

                try ctxt.clobber_reg(.RAX, as);
                try ctxt.clobber_reg(.RDX, as);
                try ctxt.clobber_cc(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("mul");

                switch (b.val) {
                    .top => {
                        try ctxt.pop_r64(.RAX, as);
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = ctxt.asm_val_mem(b) });
                    },
                    .reg => |reg| {
                        if (reg != .RAX) {
                            try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                        }
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RAX, imm);
                    },
                }

                switch (a.val) {
                    .top => {
                        try ctxt.pop_r64(.RCX, as);
                        try as.imul_rm64(.{ .reg = .RCX });
                    },
                    .mem => {
                        try as.imul_rm64(.{ .mem = ctxt.asm_val_mem(a) });
                    },
                    .reg => |reg| {
                        try as.imul_rm64(.{ .reg = reg });
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RCX, imm);
                        try as.imul_rm64(.{ .reg = .RCX });
                    },
                }

                try ctxt.vstk_push(.{ .asm_reg = .RAX });
            },
            .mod => {
                var b = try ctxt.vstk_pop_asm(as);
                const a = try ctxt.vstk_pop_asm(as);

                try ctxt.clobber_reg(.RAX, as);
                try ctxt.clobber_reg(.RDX, as);
                try ctxt.clobber_cc(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("mod");

                switch (b.val) {
                    .top => {
                        try ctxt.pop_r64(.RCX, as);
                        b.val = .{ .reg = .RCX };
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RCX, imm);
                        b.val = .{ .reg = .RCX };
                    },
                    else => {},
                }

                switch (a.val) {
                    .top => {
                        try ctxt.pop_r64(.RAX, as);
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = ctxt.asm_val_mem(a) });
                    },
                    .reg => |reg| {
                        if (reg != .RAX) {
                            try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                        }
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RAX, imm);
                    },
                }

                try as.cqo();

                switch (b.val) {
                    .mem => {
                        try as.idiv_rm64(.{ .mem = ctxt.asm_val_mem(b) });
                    },
                    .reg => |reg| {
                        try as.idiv_rm64(.{ .reg = reg });
                    },
                    else => unreachable,
                }

                try ctxt.vstk_push(.{ .asm_reg = .RDX });
            },
            .inc => {
                const v = try ctxt.vstk_pop_asm(as);

                if (v.val != .top) {
                    try ctxt.clobber_reg(.RAX, as);
                }

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("inc");

                switch (v.val) {
                    .top => {
                        try as.inc_rm64(.{ .mem = .{ .base = .RSP } });
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = ctxt.asm_val_mem(v) });
                        try as.inc_rm64(.{ .reg = .RAX });
                        try ctxt.vstk_push(.{ .asm_reg = .RAX });
                    },
                    .reg => |reg| {
                        try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                        try as.inc_rm64(.{ .reg = .RAX });
                        try ctxt.vstk_push(.{ .asm_reg = .RAX });
                    },
                    .imm => |imm| {
                        try ctxt.vstk_push(.{ .imm = imm + 1 });
                    },
                }
            },
            .dec => {
                const v = try ctxt.vstk_pop_asm(as);

                if (v.val != .top) {
                    try ctxt.clobber_reg(.RAX, as);
                }

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("dec");

                switch (v.val) {
                    .top => {
                        try as.dec_rm64(.{ .mem = .{ .base = .RSP } });
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = ctxt.asm_val_mem(v) });
                        try as.dec_rm64(.{ .reg = .RAX });
                        try ctxt.vstk_push(.{ .asm_reg = .RAX });
                    },
                    .reg => |reg| {
                        try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                        try as.dec_rm64(.{ .reg = .RAX });
                        try ctxt.vstk_push(.{ .asm_reg = .RAX });
                    },
                    .imm => |imm| {
                        try ctxt.vstk_push(.{ .imm = imm - 1 });
                    },
                }
            },
            .dup => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("dup");

                if (ctxt.vstk_get(0)) |v| {
                    if (v == .sprel) {
                        try ctxt.vstk_push(.{ .sprel = v.sprel - 1 });
                    } else {
                        try ctxt.vstk_push(v);
                    }
                } else {
                    try ctxt.vstk_push(.{ .sprel = -1 });
                }
            },
            .stack_alloc => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("stack_alloc");

                for (0..@as(usize, @intCast(insn.operand.int))) |_| {
                    try ctxt.vstk_push(.unit);
                }
            },
            inline .cmp_lt, .cmp_gt, .cmp_le, .cmp_ge, .cmp_eq, .cmp_ne => |cmp| insn: {
                var b = try ctxt.vstk_pop_asm(as);
                var a = try ctxt.vstk_pop_asm(as);
                var r = false;

                try ctxt.clobber_cc(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("cmp");
                try self.dbg_break(@tagName(cmp));

                // Immediate value must be right-hand-side
                if (a.val == .imm) {
                    const t = a;
                    a = b;
                    b = t;
                    r = !r;
                }

                switch (b.val) {
                    .top => {
                        try ctxt.pop_r64(.RSI, as);
                        b.val = .{ .reg = .RSI };
                    },
                    .mem => {
                        // Only one memory operand is allowed
                        if (a.val == .mem) {
                            try as.mov_r64_rm64(.RSI, .{ .mem = ctxt.asm_val_mem(b) });
                            b.val = .{ .reg = .RSI };
                        }
                    },
                    .imm => |imm| {
                        if (imm_size(imm) > 4) {
                            try as.mov_r64_imm64(.RSI, imm);
                            b.val = .{ .reg = .RSI };
                        }
                    },
                    else => {},
                }

                switch (a.val) {
                    .top => {
                        try ctxt.pop_r64(.RCX, as);
                        a.val = .{ .reg = .RCX };
                    },
                    else => {},
                }

                switch (a.val) {
                    .mem => {
                        switch (b.val) {
                            .reg => |reg_b| {
                                try as.cmp_rm64_r64(.{ .mem = ctxt.asm_val_mem(a) }, reg_b);
                            },
                            .imm => |imm_b| {
                                try as.cmp_rm64_imm32(.{ .mem = ctxt.asm_val_mem(a) }, @intCast(imm_b));
                            },
                            else => unreachable,
                        }
                    },
                    .reg => |reg_a| {
                        switch (b.val) {
                            .mem => |mem_b| {
                                try as.cmp_r64_rm64(reg_a, .{ .mem = mem_b });
                            },
                            .reg => |reg_b| {
                                try as.cmp_r64_rm64(reg_a, .{ .reg = reg_b });
                            },
                            .imm => |imm_b| {
                                try as.cmp_rm64_imm32(.{ .reg = reg_a }, @intCast(imm_b));
                            },
                            else => unreachable,
                        }
                    },
                    .imm => {
                        const v = switch (cmp) {
                            .cmp_lt => a.val.imm < b.val.imm,
                            .cmp_gt => a.val.imm > b.val.imm,
                            .cmp_eq => a.val.imm == b.val.imm,
                            .cmp_ne => a.val.imm != b.val.imm,
                            else => unreachable,
                        };

                        try ctxt.vstk_push(.{ .imm = if (v) 1 else 0 });

                        break :insn;
                    },
                    else => unreachable,
                }

                try ctxt.vstk_push(.{ .asm_cc = if (r) opcode_cc(cmp).reverse() else opcode_cc(cmp) });
            },
            .call => {
                try ctxt.vstk_full_sync(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("call");

                try as.push_r64(.RBP);
                try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
                try self.call_loc(insn.operand.location);
                try self.dbg_break("call_ret");

                try as.pop_r64(.RBP);
                try as.pop_r64(.RCX);
                try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });

                try ctxt.vstk_push(.{ .asm_reg = .RAX });
            },
            .syscall => {
                try ctxt.vstk_full_sync(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("syscall");

                switch (insn.operand.int) {
                    0 => {
                        try as.mov_r64_rm64(.RDI, .{ .reg = .R15 });
                        try as.mov_r64_rm64(.RSI, .{ .mem = .{ .base = .RSP } });
                        try as.mov_r64_imm64(.RAX, @bitCast(@intFromPtr(&syscall_0)));
                        try as.lea_r64(.RBX, .{ .base = .RSP, .disp = 8 });
                        try as.and_rm64_imm8(.{ .reg = .RSP }, -0x10);
                        try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RBX);
                        try as.call_rm64(.{ .reg = .RAX });
                        try self.dbg_break("syscall_ret");
                        try as.pop_r64(.RSP);
                    },
                    else => {},
                }
            },
            .ret => {
                if (ctxt.vstk_pop()) |v| {
                    // stack is being cleared, no need to sync ctxt
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("ret");
                    switch (v) {
                        .bprel => |bprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } });
                        },
                        .asm_reg => |reg| {
                            if (reg != .RAX) {
                                try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                            }
                        },
                        .imm => |imm| {
                            try as.mov_r64_imm64(.RAX, imm);
                        },
                        else => std.debug.panic("@{}: Unimplemented ctxt condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // ctxt empty, no need to sync
                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("ret");
                    try as.pop_r64(.RAX);
                }
                try as.mov_r64_rm64(.RSP, .{ .reg = .RBP });
                try as.ret_near();
            },
            .jmp => {
                try ctxt.vstk_full_sync(as);

                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("jmp");

                try self.jmp_loc(insn.operand.location);
            },
            .jmpnz => {
                if (ctxt.vstk_pop()) |v| {
                    try ctxt.vstk_full_sync(as);

                    self.insn_meta.items[i].offset = as.offset();
                    try self.dbg_break("jmpnz");

                    switch (v) {
                        .asm_reg => |reg| {
                            try as.test_rm64_r64(.{ .reg = reg }, reg);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .asm_cc => |cc| {
                            try self.jcc_loc(cc, insn.operand.location);
                        },
                        else => std.debug.panic("@{}: Unimplemented ctxt condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    try ctxt.vstk_full_sync(as);

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

                try ctxt.vstk_push(.{ .imm = insn.operand.int });
            },
            .pop => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("pop");

                if (ctxt.vstk_pop()) |_| {} else {
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = 8 });
                }
            },
            .load => {
                self.insn_meta.items[i].offset = as.offset();
                try self.dbg_break("load");

                try ctxt.vstk_push(.{ .bprel = @intCast(insn.operand.int) });
            },
            .store => {
                const rm = as_lib.RM64{ .mem = .{ .base = .RBP, .disp = @intCast(-8 * (1 + insn.operand.int)) } };

                if (ctxt.vstk_pop()) |v| {
                    try ctxt.clobber_bprel(@intCast(insn.operand.int), as);

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
                        .asm_reg => |reg| {
                            try as.mov_rm64_r64(rm, reg);
                        },
                        else => std.debug.panic("@{}: Unimplemented ctxt condition for {s}: {s}.", .{ i, @tagName(insn.op), @tagName(v) }),
                    }
                } else {
                    // ctxt empty, no need to sync
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
}

pub fn compile_program(self: *Self, prog: arch.Program) !Function {
    const as = &self.as;
    as.reset();

    self.insn_meta.clearRetainingCapacity();
    self.relocs.clearRetainingCapacity();

    // function call thunk
    try self.dbg_break("start");
    try as.push_r64(.RBP);
    try as.push_r64(.RBX);
    try as.push_r64(.R15);
    try as.mov_r64_rm64(.R15, .{ .reg = .RDI });
    try as.mov_rm64_r64(.{ .mem = .{ .base = .R15 } }, .RSP);
    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
    try self.call_loc(prog.entry);
    try self.dbg_break("end");
    try as.pop_r64(.R15);
    try as.pop_r64(.RBX);
    try as.pop_r64(.RBP);
    try as.ret_near();

    try self.compile_slice(prog.code);

    self.relocate_all();

    return Function.init(self.as.code());
}
