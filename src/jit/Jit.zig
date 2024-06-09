const std = @import("std");
const arch = @import("arch");
const as_lib = @import("as.zig");
const ExecContext = @import("ExecContext.zig");
const Function = @import("Function.zig");
const Diagnostics = @import("diagnostic").DiagnosticList;
const APIValue = @import("memory_manager").APITypes.Value;

const Self = @This();

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

const VmdVal = struct {
    pc: usize,
    tag: ?arch.Type = null,
    val: union(enum) {
        unit,
        sprel: i32,
        bprel: i32,
        gprel: i32,
        imm: i64,
        asm_reg: as_lib.R64,
        asm_cc: as_lib.CC,
    },
};

const AsmVal = struct {
    tag: ?arch.Type = null,
    val: union(enum) {
        top, // Top of the real stack
        mem: as_lib.Mem, // Memory address (RSP displacement subject to adjustment)
        reg: as_lib.R64, // Register
        imm: i64, // Immediate value
    },
    sp: i32 = undefined, // sp reference value for sp-relative memory addres
};

alloc: std.mem.Allocator,
as: as_lib.As,
pc_map: []usize,
relocs: std.ArrayList(Reloc),
dbgjit: ?[]const u8,
errors: enum { abort, ignore },
prog: *const arch.Program,
diags: ?*Diagnostics,
gprel_offset: i32,

// Virtal stack of values not yet committed to the real stack
vstk: std.ArrayList(VmdVal),

// Reference value for the "real" sp, used to adjust sp-relative memory accesses
sp: i32,

// bp-offset of the bottom of the virtual stack, if known
vstk_bp: ?i32,

pub fn init(alloc: std.mem.Allocator) Self {
    const v = APIValue { .int = 0 };

    return .{
        .alloc = alloc,
        .as = as_lib.As.init(alloc),
        .pc_map = undefined,
        .relocs = std.ArrayList(Reloc).init(alloc),
        .dbgjit = std.posix.getenv("DBGJIT"),
        .errors = .abort,
        .prog = undefined,
        .diags = null,
        .vstk = std.ArrayList(VmdVal).init(alloc),
        .sp = 0,
        .vstk_bp = 0,
        .gprel_offset = @intCast(@intFromPtr(&v.int) - @intFromPtr(&v)),
    };
}

pub fn deinit(self: *Self) void {
    self.as.deinit();
    self.relocs.deinit();
    self.vstk.deinit();
}

inline fn reset(self: *Self) void {
    self.as.reset();
    self.relocs.clearRetainingCapacity();
    self.vstk.clearRetainingCapacity();
    self.sp = 0;
    self.vstk_bp = 0;
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
        else => std.debug.panic("Invalid opcode for opcode_cc: {s}.", .{@tagName(opcode)}),
    };
}

inline fn relocate(self: *Self, reloc: Reloc) void {
    const code = self.as.code();

    const val = switch (reloc.val) {
        .off => |off| off,
        .loc => |loc| self.pc_map[loc],
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

fn vstk_push(self: *Self, value: VmdVal) !void {
    try self.vstk.append(value);
}

fn vstk_pop(self: *Self) ?VmdVal {
    if (self.vstk.items.len != 0) {
        return self.vstk.pop();
    } else {
        return null;
    }
}

fn vstk_get(self: *const Self, offset: i64) ?VmdVal {
    const n = @as(i64, @intCast(self.vstk.items.len)) + offset;

    if (n >= 0 and n < self.vstk.items.len) {
        return self.vstk.items[@as(usize, @intCast(n))];
    } else {
        return null;
    }
}

fn vstk_sync(self: *Self, offset: i64) !void {
    const as = &self.as;
    var units: i32 = 0;
    var unit_pc: usize = undefined;

    while (@as(i64, @intCast(self.vstk.items.len)) + offset > 0) {
        const v = self.vstk.orderedRemove(0);

        if (v.val == .unit) {
            units += 1;
            unit_pc = v.pc;
        } else {
            if (units != 0) {
                try self.add_diag(unit_pc, "uninitialized values cannot be compiled", .{});
                try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
                self.sp += units;
                units = 0;
            }
            switch (v.val) {
                .unit => unreachable,
                .sprel => |sprel| {
                    try as.push_rm64(.{ .mem = .{ .base = .RSP, .disp = -8 * (sprel + 1) } });
                },
                .bprel => |bprel| {
                    try as.push_rm64(.{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } });
                },
                .gprel => |gprel| {
                    try as.push_rm64(.{ .mem = .{ .base = .R14, .disp = gprel * @sizeOf(APIValue) + self.gprel_offset } });
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
        try self.add_diag(unit_pc, "uninitialized values cannot be compiled", .{});
        try as.lea_r64(.RSP, .{ .base = .RSP, .disp = -units * 8 });
        self.sp += units;
    }
}

fn vstk_full_sync(self: *Self) !void {
    try self.vstk_sync(0);
    self.sp = 0;
    self.vstk_bp = null;
}

fn clobber_reg(self: *Self, reg: as_lib.R64) !void {
    const b = 1 - @as(i64, @intCast(self.vstk.items.len));

    for (0..self.vstk.items.len) |i| {
        const j = self.vstk.items.len - 1 - i;
        const v = self.vstk.items[j];
        if (v.val == .asm_reg and v.val.asm_reg == reg) {
            return self.vstk_sync(b + @as(i64, @intCast(j)));
        }
    }
}

fn clobber_cc(self: *Self) !void {
    const b = 1 - @as(i64, @intCast(self.vstk.items.len));

    for (0..self.vstk.items.len) |i| {
        const j = self.vstk.items.len - 1 - i;
        const v = self.vstk.items[j];
        if (v.val == .asm_cc) {
            return self.vstk_sync(b + @as(i64, @intCast(i)));
        }
    }
}

fn clobber_bprel(self: *Self, bprel: i32) !void {
    const b = 1 - @as(i64, @intCast(self.vstk.items.len));

    for (0..self.vstk.items.len) |i| {
        const j = self.vstk.items.len - 1 - i;
        const v = self.vstk.items[j];
        if (v.val == .bprel and v.val.bprel == bprel) {
            return self.vstk_sync(b + @as(i64, @intCast(i)));
        }
    }
}

fn vstk_pop_asm(self: *Self) !AsmVal {
    const as = &self.as;

    if (self.vstk_pop()) |v| {
        switch (v.val) {
            .unit => {
                try self.add_diag(v.pc, "uninitialized values cannot be compiled", .{});
                return .{ .tag = v.tag, .val = .{ .imm = 0 } };
            },
            .sprel => |sprel| {
                try self.vstk_sync(sprel + 1);
                return .{ .tag = v.tag, .val = .{ .mem = .{ .base = .RSP, .disp = -8 * (sprel + 1 + @as(i32, @intCast(self.vstk.items.len))) } }, .sp = self.sp };
            },
            .bprel => |bprel| {
                return .{ .tag = v.tag, .val = .{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } } };
            },
            .gprel => |gprel| {
                return .{ .tag = v.tag, .val = .{ .mem = .{ .base = .R14, .disp = gprel * @sizeOf(APIValue) + self.gprel_offset } } };
            },
            .imm => |imm| {
                return .{ .tag = v.tag, .val = .{ .imm = imm } };
            },
            .asm_reg => |reg| {
                return .{ .tag = v.tag, .val = .{ .reg = reg } };
            },
            .asm_cc => |cc| {
                try as.setcc_rm8(cc, .{ .reg = .R8L });
                try as.movzx_r64_rm8(.R8, .{ .reg = .R8L });
                return .{ .tag = .int, .val = .{ .reg = .R8 } };
            },
        }
    } else {
        return .{ .val = .top };
    }
}

// Emit a push instruction and adjust reference sp
fn push_rm64(self: *Self, rm: as_lib.RM64) !void {
    try self.as.push_rm64(rm);

    self.sp += 1;
}

// Emit a pop instruction and adjust reference sp
fn pop_r64(self: *Self, reg: as_lib.R64) !void {
    try self.as.pop_r64(reg);

    self.sp -= 1;
}

// Adjust the displacement of a memory asm val according to the reference sp
fn asm_val_mem(self: *Self, v: AsmVal) as_lib.Mem {
    var mem = v.val.mem;

    if (mem.base == .RSP) {
        mem.disp -= (v.sp - self.sp) * 8;
    }

    return mem;
}

inline fn add_diag(self: *Self, pc: ?usize, fmt: []const u8, args: anytype) !void {
    if (self.diags) |dg| {
        var loc: ?[]const u8 = null;

        if (self.prog.tokens) |t| {
            if (pc) |p| {
                if (p < t.len and t[p].len != 0) {
                    loc = t[p];
                }
            }
        }

        try dg.addDiagnostic(.{
            .description = .{ .dynamic = try dg.newDynamicDescription(fmt, args) },
            .location = loc,
        });
    }

    if (self.errors == .abort) {
        return error.CompileError;
    }
}

fn compile_slice(self: *Self, code: []const arch.Instruction, start_pc: usize) !void {
    const as = &self.as;

    const func_map = try self.alloc.alloc(bool, code.len);
    const edge_map = try self.alloc.alloc(bool, code.len);
    defer self.alloc.free(func_map);
    defer self.alloc.free(edge_map);

    @memset(func_map, false);
    @memset(edge_map, false);

    if (self.prog.entry >= start_pc and self.prog.entry < start_pc + code.len) {
        func_map[self.prog.entry - start_pc] = true;
    }

    for (code) |insn| {
        switch (insn.op) {
            .call => {
                const loc = insn.operand.location;
                if (loc >= start_pc and loc < start_pc + code.len) {
                    func_map[loc - start_pc] = true;
                }
            },
            .jmp, .jmpnz => {
                const loc = insn.operand.location;
                if (loc < start_pc or loc >= start_pc + code.len) {
                    @panic("Cross-slice jumps are not supported.");
                }
                edge_map[loc - start_pc] = true;
            },
            else => {},
        }
    }

    for (0.., code) |i, insn| {
        const pc = start_pc + i;

        if (func_map[i]) {
            self.vstk_bp = 0;
        }

        if (edge_map[i]) {
            for (self.vstk.items) |v| {
                if (v.tag == .unit) {
                    try self.add_diag(v.pc, "uninitialized values cannot be compiled", .{});
                }
            }

            try self.vstk_full_sync();
        }

        switch (insn.op) {
            .add => {
                try self.vstk_full_sync();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                try as.pop_r64(.RCX);
                try as.add_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .sub => {
                try self.vstk_full_sync();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                try as.pop_r64(.RCX);
                try as.sub_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
            },
            .mul => {
                var b = try self.vstk_pop_asm();
                var a = try self.vstk_pop_asm();

                try self.clobber_reg(.RAX);
                try self.clobber_reg(.RDX);
                try self.clobber_cc();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                if (a.val == .reg and a.val.reg == .RAX) {
                    const t = a;
                    a = b;
                    b = t;
                }

                switch (b.val) {
                    .top => {
                        try self.pop_r64(.RAX);
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = self.asm_val_mem(b) });
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
                        try self.pop_r64(.RCX);
                        try as.imul_rm64(.{ .reg = .RCX });
                    },
                    .mem => {
                        try as.imul_rm64(.{ .mem = self.asm_val_mem(a) });
                    },
                    .reg => |reg| {
                        try as.imul_rm64(.{ .reg = reg });
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RCX, imm);
                        try as.imul_rm64(.{ .reg = .RCX });
                    },
                }

                try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_reg = .RAX } });
            },
            .div, .mod => {
                var b = try self.vstk_pop_asm();
                const a = try self.vstk_pop_asm();

                try self.clobber_reg(.RAX);
                try self.clobber_reg(.RDX);
                try self.clobber_cc();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                switch (b.val) {
                    .top => {
                        try self.pop_r64(.RCX);
                        b.val = .{ .reg = .RCX };
                    },
                    .reg => |reg| {
                        if (reg == .RAX) {
                            try as.mov_r64_rm64(.RCX, .{ .reg = reg });
                            b.val = .{ .reg = .RCX };
                        }
                    },
                    .imm => |imm| {
                        try as.mov_r64_imm64(.RCX, imm);
                        b.val = .{ .reg = .RCX };
                    },
                    else => {},
                }

                switch (a.val) {
                    .top => {
                        try self.pop_r64(.RAX);
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = self.asm_val_mem(a) });
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
                        try as.idiv_rm64(.{ .mem = self.asm_val_mem(b) });
                    },
                    .reg => |reg| {
                        try as.idiv_rm64(.{ .reg = reg });
                    },
                    else => unreachable,
                }

                if (insn.op == .div) {
                    try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_reg = .RAX } });
                } else {
                    try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_reg = .RDX } });
                }
            },
            .inc, .dec => {
                const v = try self.vstk_pop_asm();

                if (v.val != .top) {
                    try self.clobber_reg(.RAX);
                }

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                switch (v.val) {
                    .top => {
                        if (insn.op == .inc) {
                            try as.inc_rm64(.{ .mem = .{ .base = .RSP } });
                        } else {
                            try as.dec_rm64(.{ .mem = .{ .base = .RSP } });
                        }
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RAX, .{ .mem = self.asm_val_mem(v) });
                        if (insn.op == .inc) {
                            try as.inc_rm64(.{ .reg = .RAX });
                        } else {
                            try as.dec_rm64(.{ .reg = .RAX });
                        }
                        try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_reg = .RAX } });
                    },
                    .reg => |reg| {
                        if (reg != .RAX) {
                            try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                        }
                        if (insn.op == .inc) {
                            try as.inc_rm64(.{ .reg = .RAX });
                        } else {
                            try as.dec_rm64(.{ .reg = .RAX });
                        }
                        try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_reg = .RAX } });
                    },
                    .imm => |imm| {
                        try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .imm = imm + 1 } });
                    },
                }
            },
            .dup => {
                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                if (self.vstk_get(-1)) |v| {
                    if (v.val == .sprel) {
                        try self.vstk_push(.{ .pc = pc, .tag = v.tag, .val = .{ .sprel = v.val.sprel - 1 } });
                    } else {
                        try self.vstk_push(v);
                    }
                } else {
                    try self.vstk_push(.{ .pc = pc, .val = .{ .sprel = -1 } });
                }
            },
            .stack_alloc => {
                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                for (0..@as(usize, @intCast(insn.operand.int))) |_| {
                    try self.vstk_push(.{ .pc = pc, .tag = .unit, .val = .unit });
                }
            },
            inline .cmp_lt, .cmp_gt, .cmp_le, .cmp_ge, .cmp_eq, .cmp_ne => |cmp| insn: {
                var b = try self.vstk_pop_asm();
                var a = try self.vstk_pop_asm();
                var r = false;

                try self.clobber_cc();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                // Immediate value must be right-hand-side
                if (a.val == .imm) {
                    const t = a;
                    a = b;
                    b = t;
                    r = !r;
                }

                switch (b.val) {
                    .top => {
                        try self.pop_r64(.RSI);
                        b.val = .{ .reg = .RSI };
                    },
                    .mem => {
                        // Only one memory operand is allowed
                        if (a.val == .mem) {
                            try as.mov_r64_rm64(.RSI, .{ .mem = self.asm_val_mem(b) });
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
                        try self.pop_r64(.RCX);
                        a.val = .{ .reg = .RCX };
                    },
                    else => {},
                }

                switch (a.val) {
                    .mem => {
                        switch (b.val) {
                            .reg => |reg_b| {
                                try as.cmp_rm64_r64(.{ .mem = self.asm_val_mem(a) }, reg_b);
                            },
                            .imm => |imm_b| {
                                try as.cmp_rm64_imm32(.{ .mem = self.asm_val_mem(a) }, @intCast(imm_b));
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
                            // Operands have been reordered if this branch is reached, so reverse the comparison
                            .cmp_lt => b.val.imm < a.val.imm,
                            .cmp_gt => b.val.imm > a.val.imm,
                            .cmp_le => b.val.imm <= a.val.imm,
                            .cmp_ge => b.val.imm >= a.val.imm,
                            .cmp_eq => b.val.imm == a.val.imm,
                            .cmp_ne => b.val.imm != a.val.imm,
                            else => unreachable,
                        };

                        try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .imm = if (v) 1 else 0 } });

                        break :insn;
                    },
                    else => unreachable,
                }

                try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .asm_cc = if (r) opcode_cc(cmp).reverse() else opcode_cc(cmp) } });
            },
            .call => {
                const v = self.vstk_get(-1);

                if (v != null and v.?.val == .imm) {
                    const n: i32 = @intCast(v.?.val.imm);

                    try self.vstk_sync(0);

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    try as.push_r64(.RBP);
                    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
                    try self.call_loc(insn.operand.location);
                    try self.dbg_break("call_ret");

                    try as.pop_r64(.RBP);
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = 8 * (n + 1) });
                    self.sp -= n + 1;

                    try self.vstk_push(.{ .pc = pc, .val = .{ .asm_reg = .RAX } });
                } else {
                    try self.vstk_full_sync();

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    try as.push_r64(.RBP);
                    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
                    try self.call_loc(insn.operand.location);
                    try self.dbg_break("call_ret");

                    try as.pop_r64(.RBP);
                    try as.pop_r64(.RCX);
                    try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });

                    try self.vstk_push(.{ .pc = pc, .val = .{ .asm_reg = .RAX } });
                }
            },
            .syscall => {
                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                switch (insn.operand.int) {
                    0...1 => |syscall| {
                        try self.vstk_sync(0);

                        try as.mov_r64_rm64(.RDI, .{ .reg = .R15 });
                        try as.mov_r64_rm64(.RSI, .{ .mem = .{ .base = .RSP } });
                        try as.lea_r64(.RCX, .{ .base = .RSP, .disp = 8 });
                        try as.and_rm64_imm8(.{ .reg = .RSP }, -0x10);
                        try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RCX);
                        try as.call_rm64(.{ .mem = .{ .base = .R15, .disp = @offsetOf(ExecContext, "syscall_tbl") + @as(i32, @intCast(syscall * 8)) } });
                        try self.dbg_break("syscall_ret");
                        try as.pop_r64(.RSP);

                        self.sp -= 1;
                    },
                    else => {},
                }
            },
            .ret => {
                if (self.vstk_pop()) |v| {
                    if (v.val == .sprel) {
                        try self.vstk_sync(v.val.sprel + 1);
                    } else {
                        // stack is being cleared, no need to sync vstk
                    }

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    switch (v.val) {
                        .unit => {
                            try self.add_diag(v.pc, "uninitialized values cannot be compiled", .{});
                            try as.xor_r64_rm64(.RAX, .{ .reg = .RAX });
                        },
                        .sprel => |sprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RSP, .disp = -8 * (sprel + 1 + @as(i32, @intCast(self.vstk.items.len))) } });
                        },
                        .bprel => |bprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .disp = -8 * (bprel + 1) } });
                        },
                        .gprel => |gprel| {
                            try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .R14, .disp = gprel * @sizeOf(APIValue) + self.gprel_offset } });
                        },
                        .imm => |imm| {
                            try as.mov_r64_imm64(.RAX, imm);
                        },
                        .asm_reg => |reg| {
                            if (reg != .RAX) {
                                try as.mov_r64_rm64(.RAX, .{ .reg = reg });
                            }
                        },
                        .asm_cc => |cc| {
                            try as.setcc_rm8(cc, .{ .reg = .AL });
                            try as.movzx_r64_rm8(.RAX, .{ .reg = .AL });
                        },
                    }
                } else {
                    // vstk empty, no need to sync
                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    try as.pop_r64(.RAX);
                }
                try as.mov_r64_rm64(.RSP, .{ .reg = .RBP });
                try as.ret_near();
            },
            .jmp => {
                try self.vstk_sync(0);

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                try self.jmp_loc(insn.operand.location);
            },
            .jmpnz => {
                if (self.vstk_pop()) |v| {
                    try self.vstk_sync(0);

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    switch (v.val) {
                        .unit => {
                            try self.add_diag(v.pc, "uninitialized values cannot be compiled", .{});
                        },
                        .sprel => |sprel| {
                            try as.mov_r64_rm64(.RCX, .{ .mem = .{ .base = .RSP, .disp = @intCast(-8 * (sprel + 1)) } });
                            try as.test_rm64_r64(.{ .reg = .RCX }, .RCX);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .bprel => |bprel| {
                            try as.mov_r64_rm64(.RCX, .{ .mem = .{ .base = .RBP, .disp = @intCast(-8 * (bprel + 1)) } });
                            try as.test_rm64_r64(.{ .reg = .RCX }, .RCX);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .gprel => |gprel| {
                            try as.mov_r64_rm64(.RCX, .{ .mem = .{ .base = .R14, .disp = gprel * @sizeOf(APIValue) + self.gprel_offset } });
                            try as.test_rm64_r64(.{ .reg = .RCX }, .RCX);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .imm => |imm| {
                            if (imm != 0) {
                                try self.jmp_loc(insn.operand.location);
                            }
                        },
                        .asm_reg => |reg| {
                            try as.test_rm64_r64(.{ .reg = reg }, reg);
                            try self.jcc_loc(.NE, insn.operand.location);
                        },
                        .asm_cc => |cc| {
                            try self.jcc_loc(cc, insn.operand.location);
                        },
                    }
                } else {
                    try self.vstk_sync(0);

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    try as.pop_r64(.RCX);
                    try as.test_rm64_r64(.{ .reg = .RCX }, .RCX);
                    try self.jcc_loc(.NE, insn.operand.location);
                }
            },
            .push => {
                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                try self.vstk_push(.{ .pc = pc, .tag = .int, .val = .{ .imm = insn.operand.int } });
            },
            .pop => {
                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                if (self.vstk_pop()) |_| {} else {
                    try as.lea_r64(.RSP, .{ .base = .RSP, .disp = 8 });
                    self.sp -= 1;
                }
            },
            .load => {
                const offset = insn.operand.int;

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                if (self.vstk_bp != null and offset >= self.vstk_bp.? + self.sp) {
                    if (offset - (self.vstk_bp.? + self.sp) >= self.vstk.items.len) {
                        try self.add_diag(pc, "load above stack pointer", .{});
                    } else {
                        var v = self.vstk.items[@intCast(offset - (self.vstk_bp.? + self.sp))];
                        v.pc = pc;

                        try self.vstk_push(v);
                    }
                } else {
                    try self.vstk_push(.{ .pc = pc, .val = .{ .bprel = @intCast(offset) } });
                }
            },
            .store => {
                const offset = insn.operand.int;

                if (self.vstk_bp != null and offset >= self.vstk_bp.? + self.sp and self.vstk.items.len != 0) {
                    if (offset - (self.vstk_bp.? + self.sp) >= self.vstk.items.len) {
                        try self.add_diag(pc, "store above stack pointer", .{});
                    } else {
                        const from = self.vstk.items.len - 1;
                        const to = offset - (self.vstk_bp.? + self.sp);

                        if (from != to) {
                            self.vstk.items[@intCast(to)] = self.vstk.pop();
                        }
                    }
                } else {
                    const rm = as_lib.RM64{ .mem = .{ .base = .RBP, .disp = @intCast(-8 * (1 + insn.operand.int)) } };
                    const v = try self.vstk_pop_asm();

                    try self.clobber_bprel(@intCast(insn.operand.int));

                    self.pc_map[pc] = as.offset();
                    try self.dbg_break(@tagName(insn.op));

                    switch (v.val) {
                        .top => {
                            try self.pop_r64(.RCX);
                            try as.mov_rm64_r64(rm, .RCX);
                        },
                        .mem => {
                            try as.mov_r64_rm64(.RCX, .{ .mem = self.asm_val_mem(v) });
                            try as.mov_rm64_r64(rm, .RCX);
                        },
                        .reg => |reg| {
                            try as.mov_rm64_r64(rm, reg);
                        },
                        .imm => |imm| {
                            if (imm_size(imm) > 4) {
                                try as.mov_r64_imm64(.RCX, imm);
                                try as.mov_rm64_r64(rm, .RCX);
                            } else {
                                try as.mov_rm64_imm32(rm, @intCast(imm));
                            }
                        },
                    }
                }
            },
            .glob_load => {
                const offset = insn.operand.int;

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                try self.vstk_push(.{ .pc = pc, .val = .{ .gprel = @intCast(offset) } });
            },
            .glob_store => {
                const offset = insn.operand.int;

                const rm = as_lib.RM64{ .mem = .{ .base = .R14, .disp = @intCast(offset * @sizeOf(APIValue) + self.gprel_offset) } };
                const v = try self.vstk_pop_asm();

                self.pc_map[pc] = as.offset();
                try self.dbg_break(@tagName(insn.op));

                switch (v.val) {
                    .top => {
                        try self.pop_r64(.RCX);
                        try as.mov_rm64_r64(rm, .RCX);
                    },
                    .mem => {
                        try as.mov_r64_rm64(.RCX, .{ .mem = self.asm_val_mem(v) });
                        try as.mov_rm64_r64(rm, .RCX);
                    },
                    .reg => |reg| {
                        try as.mov_rm64_r64(rm, reg);
                    },
                    .imm => |imm| {
                        if (imm_size(imm) > 4) {
                            try as.mov_r64_imm64(.RCX, imm);
                            try as.mov_rm64_r64(rm, .RCX);
                        } else {
                            try as.mov_rm64_imm32(rm, @intCast(imm));
                        }
                    },
                }
            },
            else => {
                try self.add_diag(pc, "operation not compilable: {s}", .{@tagName(insn.op)});
            },
        }
    }
}

pub fn compile_program(self: *Self, prog: arch.Program, diags: ?*Diagnostics) !Function {
    self.reset();

    self.prog = &prog;
    self.diags = diags;

    const as = &self.as;

    // Function call thunk
    try self.dbg_break("start");
    try self.dbg_break("program");
    // Save caller registers
    try as.push_r64(.R15);
    try as.push_r64(.R14);
    // Save ExecutionContext pointer
    try as.mov_r64_rm64(.R15, .{ .reg = .RDI });
    // Save global pointer
    try as.mov_r64_rm64(.R14, .{ .mem = .{ .base = .R15, .disp = @offsetOf(ExecContext, "gp") } });
    // Set arguments
    try as.push_imm8(0);
    try as.push_r64(.RBP);
    // Save unwind sp
    try as.mov_rm64_r64(.{ .mem = .{ .base = .R15, .disp = @offsetOf(ExecContext, "unwind_sp") } }, .RSP);
    // Call compiled function
    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
    try self.call_loc(prog.entry);
    try self.dbg_break("end");
    // Stack cleanup
    try as.pop_r64(.RBP);
    try as.pop_r64(.RCX);
    try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });
    // Restore caller registers
    try as.pop_r64(.R14);
    try as.pop_r64(.R15);
    try as.ret_near();

    self.pc_map = try self.alloc.alloc(usize, prog.code.len + 1);
    errdefer self.alloc.free(self.pc_map);

    try self.compile_slice(prog.code, 0);

    self.pc_map[prog.code.len] = self.as.offset();
    self.relocate_all();

    return Function.init(self.alloc, self.as.code(), self.pc_map);
}

pub fn compile_partial(self: *Self, prog: arch.Program, slices: []const []const arch.Instruction, diags: ?*Diagnostics) !Function {
    self.reset();

    self.prog = &prog;
    self.diags = diags;

    const as = &self.as;

    // Function call thunk
    try self.dbg_break("start");
    try self.dbg_break("partial");
    // Save caller registers
    try as.push_r64(.R15);
    try as.push_r64(.R14);
    // Save ExecutionContext pointer
    try as.mov_r64_rm64(.R15, .{ .reg = .RDI });
    // Save global pointer
    try as.mov_r64_rm64(.R14, .{ .mem = .{ .base = .R15, .disp = @offsetOf(ExecContext, "gp") } });
    // Save function pointer argument
    try as.mov_r64_rm64(.RAX, .{ .reg = .RCX });
    // Copy function arguments to stack
    try as.mov_r64_rm64(.RCX, .{ .reg = .RDX });
    try as.sal_rm64_imm8(.{ .reg = .RDX }, 3);
    try as.sub_r64_rm64(.RSP, .{ .reg = .RDX });
    try as.mov_r64_rm64(.RDI, .{ .reg = .RSP });
    try as.push_r64(.RCX);
    try as.cld();
    try as.rep();
    try as.movsq();
    try as.push_r64(.RBP);
    // Save unwind sp
    try as.mov_rm64_r64(.{ .mem = .{ .base = .R15, .disp = @offsetOf(ExecContext, "unwind_sp") } }, .RSP);
    // Call compiled function
    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
    try as.call_rm64(.{ .reg = .RAX });
    try self.dbg_break("end");
    // Stack cleanup
    try as.pop_r64(.RBP);
    try as.pop_r64(.RCX);
    try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });
    // Restore caller registers
    try as.pop_r64(.R14);
    try as.pop_r64(.R15);
    try as.ret_near();

    self.pc_map = try self.alloc.alloc(usize, prog.code.len + 1);
    errdefer self.alloc.free(self.pc_map);
    @memset(self.pc_map, 0);

    for (slices) |s| {
        const start = (@intFromPtr(s.ptr) - @intFromPtr(prog.code.ptr)) / @sizeOf(@TypeOf(s[0]));
        try self.compile_slice(s, start);
    }

    self.pc_map[prog.code.len] = self.as.offset();
    self.relocate_all();

    return Function.init(self.alloc, self.as.code(), self.pc_map);
}
