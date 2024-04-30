const std = @import("std");
const arch = @import("arch");

const Self = @This();

const Reloc = struct {
    off: usize,
    loc: usize,
};

code: std.ArrayList(u8),
insn_map: std.ArrayList(usize),
relocs: std.ArrayList(Reloc),

const R64 = enum(u8) {
    RAX = 0x0,
    RCX = 0x1,
    RDX = 0x2,
    RBX = 0x3,
    RSP = 0x4,
    RBP = 0x5,
    RSI = 0x6,
    RDI = 0x7,
    R8 = 0x8,
    R9 = 0x9,
    R10 = 0xA,
    R11 = 0xB,
    R12 = 0xC,
    R13 = 0xD,
    R14 = 0xE,
    R15 = 0xF,
};

const REX = struct {
    W: bool = false,
    R: bool = false,
    X: bool = false,
    B: bool = false,
};

const MOD = enum(u8) {
    sib = 0b00,
    sib_disp8 = 0b01,
    sib_disp32 = 0b10,
    rm = 0b11,
};

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .code = std.ArrayList(u8).init(alloc),
        .insn_map = std.ArrayList(usize).init(alloc),
        .relocs = std.ArrayList(Reloc).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.code.deinit();
    self.insn_map.deinit();
    self.relocs.deinit();
}

fn syscall(v: i64) callconv(.C) void {
    const output_stream = std.io.getStdOut();
    const output_writer = output_stream.writer();

    output_writer.print("{}\n", .{v}) catch {};
}

pub fn compile(self: *Self, prog: arch.Program) !void {
    //try self.int3();
    try self.push_r64(.RBX);
    try self.push_r64(.RBP);
    try self.mov_r64_r64(.RBP, .RSP);
    try self.mov_r64_imm64(.RAX, -8);
    try self.add_r64_r64(.RBP, .RAX);
    try self.call_loc(prog.entry);
    try self.pop_r64(.RBP);
    try self.pop_r64(.RBX);
    try self.ret_near();

    for (prog.code) |i| {
        try self.insn_map.append(self.offset());

        switch (i.op) {
            .add => {
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.add_r64_r64(.RAX, .RBX);
                try self.push_r64(.RAX);
            },
            .sub => {
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.sub_r64_r64(.RAX, .RBX);
                try self.push_r64(.RAX);
            },
            .mul => {
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.imul_r64(.RBX);
                try self.push_r64(.RAX);
            },
            .mod => {
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.cqo();
                try self.idiv_r64(.RBX);
                try self.push_r64(.RDX);
            },
            .inc => {
                try self.pop_r64(.RAX);
                try self.inc_r64(.RAX);
                try self.push_r64(.RAX);
            },
            .dec => {
                try self.pop_r64(.RAX);
                try self.dec_r64(.RAX);
                try self.push_r64(.RAX);
            },
            .dup => {
                try self.pop_r64(.RAX);
                try self.push_r64(.RAX);
                try self.push_r64(.RAX);
            },
            .stack_alloc => {
                try self.mov_r64_imm64(.RAX, i.operand.int * 8);
                try self.sub_r64_r64(.RSP, .RAX);
            },
            .cmp_lt => {
                try self.xor_r64_r64(.RCX, .RCX);
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.cmp_r64_r64(.RAX, .RBX);
                try self.setcc_r8(.RCX, 0xC);
                try self.push_r64(.RCX);
            },
            .cmp_gt => {
                try self.xor_r64_r64(.RCX, .RCX);
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.cmp_r64_r64(.RAX, .RBX);
                try self.setcc_r8(.RCX, 0xF);
                try self.push_r64(.RCX);
            },
            .cmp_eq => {
                try self.xor_r64_r64(.RCX, .RCX);
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.cmp_r64_r64(.RAX, .RBX);
                try self.setcc_r8(.RCX, 0x4);
                try self.push_r64(.RCX);
            },
            .cmp_ne => {
                try self.xor_r64_r64(.RCX, .RCX);
                try self.pop_r64(.RBX);
                try self.pop_r64(.RAX);
                try self.cmp_r64_r64(.RAX, .RBX);
                try self.setcc_r8(.RCX, 0x5);
                try self.push_r64(.RCX);
            },
            .call => {
                try self.push_r64(.RBP);
                try self.mov_r64_r64(.RBP, .RSP);
                try self.mov_r64_imm64(.RAX, -8);
                try self.add_r64_r64(.RBP, .RAX);
                try self.call_loc(i.operand.location);
                try self.pop_r64(.RBP);
                try self.pop_r64(.RCX);
                try self.mov_r64_r64(.RSI, .RSP);
                try self.lea_r64(.RSI, .RSI, .RCX, 8);
                try self.mov_r64_r64(.RSP, .RSI);
                try self.push_r64(.RAX);
            },
            .syscall => {
                try self.mov_r64_imm64(.RAX, @bitCast(@intFromPtr(&syscall)));
                try self.pop_r64(.RDI);
                try self.mov_r64_imm64(.RBX, 0x8);
                try self.test_r64_r64(.RSP, .RBX);
                try self.jcc_rel(0x5, 2 + 5);
                try self.call_r64(.RAX);
                try self.jmp_rel(10 + 3 + 2 + 3);
                try self.sub_r64_r64(.RSP, .RBX);
                try self.call_r64(.RAX);
                try self.add_r64_r64(.RSP, .RBX);
            },
            .ret => {
                try self.pop_r64(.RAX);
                try self.mov_r64_r64(.RSP, .RBP);
                try self.ret_near();
            },
            .jmp => {
                try self.jmp_loc(i.operand.location);
            },
            .jmpnz => {
                try self.pop_r64(.RAX);
                try self.test_r64_r64(.RAX, .RAX);
                try self.jcc_loc(0x5, i.operand.location);
            },
            .push => {
                try self.mov_r64_imm64(.RAX, i.operand.int);
                try self.push_r64(.RAX);
            },
            .load => {
                try self.mov_r64_imm64(.RCX, -i.operand.int - 1);
                try self.mov_r64_m64(.RAX, .RBP, .RCX, 8);
                try self.push_r64(.RAX);
            },
            .store => {
                try self.pop_r64(.RAX);
                try self.mov_r64_imm64(.RCX, -i.operand.int - 1);
                try self.mov_m64_r64(.RBP, .RCX, 8, .RAX);
            },
            else => {
                std.debug.print("unimplemented instruction: {s}\n", .{@tagName(i.op)});
            },
        }
    }

    self.relocate();
}

pub fn relocate(self: *Self) void {
    for (self.relocs.items) |r| {
        const off = self.insn_map.items[r.loc] -% (r.off + 0x4);
        self.code.items[r.off + 0x0] = @truncate(off >> 0);
        self.code.items[r.off + 0x1] = @truncate(off >> 8);
        self.code.items[r.off + 0x2] = @truncate(off >> 16);
        self.code.items[r.off + 0x3] = @truncate(off >> 24);
    }
}

pub fn execute(self: *Self) !i64 {
    const size = self.code.items.len;

    // PROT_READ | PROT_WRITE
    const addr = std.os.linux.mmap(null, size, 0x1 | 0x2, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr: ?[*]u8 = @ptrFromInt(addr);

    if (ptr == null) {
        return error.OutOfMemory;
    }

    @memcpy(ptr.?, self.code.items);

    // PROT_READ | PROT_EXEC
    if (std.os.linux.mprotect(ptr.?, size, 0x1 | 0x4) != 0) {
        return error.AccessDenied;
    }

    const fun: ?*fn () callconv(.C) i64 = @ptrCast(ptr);
    const ret = fun.?();

    _ = std.os.linux.munmap(ptr.?, size);

    return ret;
}

pub fn offset(self: *Self) usize {
    return self.code.items.len;
}

pub fn byte(self: *Self, v: u8) !void {
    try self.code.append(v);
}

pub fn word(self: *Self, v: u16) !void {
    try self.byte(@truncate(v >> 0));
    try self.byte(@truncate(v >> 8));
}

pub fn dword(self: *Self, v: u32) !void {
    try self.word(@truncate(v >> 0));
    try self.word(@truncate(v >> 16));
}

pub fn qword(self: *Self, v: u64) !void {
    try self.dword(@truncate(v >> 0));
    try self.dword(@truncate(v >> 32));
}

pub fn reg_ex(r: R64) bool {
    return @intFromEnum(r) >= @intFromEnum(R64.R8);
}

pub fn rex_byte(self: *Self, r: REX) !void {
    var v: u8 = 0x40;

    if (r.W) {
        v |= 0x08;
    }
    if (r.R) {
        v |= 0x04;
    }
    if (r.X) {
        v |= 0x02;
    }
    if (r.B) {
        v |= 0x01;
    }

    try self.byte(v);
}

pub fn op_reg_byte(self: *Self, op: u8, reg: R64) !void {
    var v: u8 = 0;

    v |= op;
    v |= (@intFromEnum(reg) & 0b111);

    try self.byte(v);
}

pub fn modrm_byte(self: *Self, mod: MOD, reg: R64, rm: R64) !void {
    var v: u8 = 0;

    v |= (@intFromEnum(mod) & 0b11) << 6;
    v |= (@intFromEnum(reg) & 0b111) << 3;
    v |= (@intFromEnum(rm) & 0b111) << 0;

    try self.byte(v);
}

pub fn sib_byte(self: *Self, base: R64, index: R64, scale: u8) !void {
    var v: u8 = 0;

    if (scale == 1) {
        v |= (0b00) << 6;
    } else if (scale == 2) {
        v |= (0b01) << 6;
    } else if (scale == 4) {
        v |= (0b10) << 6;
    } else if (scale == 8) {
        v |= (0b11) << 6;
    } else {
        @panic("bad scale");
    }
    v |= (@intFromEnum(index) & 0b111) << 3;
    v |= (@intFromEnum(base) & 0b111) << 0;

    try self.byte(v);
}

pub fn add_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(p), .B = reg_ex(r) });
    try self.byte(0x01);
    try self.modrm_byte(.rm, p, r);
}

pub fn call_loc(self: *Self, loc: usize) !void {
    try self.byte(0xE8);
    try self.relocs.append(.{ .off = self.offset(), .loc = loc });
    try self.dword(0);
}

pub fn call_r64(self: *Self, r: R64) !void {
    if (reg_ex(r)) {
        try self.rex_byte(.{ .B = true });
    }
    try self.byte(0xFF);
    try self.modrm_byte(.rm, @enumFromInt(2), r);
}

pub fn cmp_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .B = reg_ex(p) });
    try self.byte(0x3B);
    try self.modrm_byte(.rm, r, p);
}

pub fn cqo(self: *Self) !void {
    try self.rex_byte(.{ .W = true });
    try self.byte(0x99);
}

pub fn dec_r64(self: *Self, r: R64) !void {
    try self.rex_byte(.{ .W = true, .B = reg_ex(r) });
    try self.byte(0xFF);
    try self.modrm_byte(.rm, @enumFromInt(1), r);
}

pub fn idiv_r64(self: *Self, r: R64) !void {
    try self.rex_byte(.{ .W = true, .B = reg_ex(r) });
    try self.byte(0xF7);
    try self.modrm_byte(.rm, @enumFromInt(7), r);
}

pub fn imul_r64(self: *Self, r: R64) !void {
    try self.rex_byte(.{ .W = true, .B = reg_ex(r) });
    try self.byte(0xF7);
    try self.modrm_byte(.rm, @enumFromInt(5), r);
}

pub fn inc_r64(self: *Self, r: R64) !void {
    try self.rex_byte(.{ .W = true, .B = reg_ex(r) });
    try self.byte(0xFF);
    try self.modrm_byte(.rm, @enumFromInt(0), r);
}

pub fn int3(self: *Self) !void {
    try self.byte(0xCC);
}

pub fn jcc_loc(self: *Self, cc: u8, loc: usize) !void {
    try self.byte(0x0F);
    try self.byte(0x80 + cc);
    try self.relocs.append(.{ .off = self.offset(), .loc = loc });
    try self.dword(0);
}

pub fn jcc_rel(self: *Self, cc: u8, off: i32) !void {
    try self.byte(0x0F);
    try self.byte(0x80 + cc);
    try self.dword(@bitCast(off));
}

pub fn jmp_loc(self: *Self, loc: usize) !void {
    try self.byte(0xE9);
    try self.relocs.append(.{ .off = self.offset(), .loc = loc });
    try self.dword(0);
}

pub fn jmp_rel(self: *Self, off: i32) !void {
    try self.byte(0xE9);
    try self.dword(@bitCast(off));
}

pub fn lea_r64(self: *Self, r: R64, base: R64, index: R64, scale: u8) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .X = reg_ex(index), .B = reg_ex(base) });
    try self.byte(0x8D);
    if (base == R64.RBP) {
        try self.modrm_byte(.sib_disp8, r, .RSP);
        try self.sib_byte(base, index, scale);
        try self.byte(0x0);
    } else {
        try self.modrm_byte(.sib, r, .RSP);
        try self.sib_byte(base, index, scale);
    }
}

pub fn mov_r64_imm64(self: *Self, r: R64, v: i64) !void {
    try self.rex_byte(.{ .W = true, .B = reg_ex(r) });
    try self.op_reg_byte(0xB8, r);
    try self.qword(@bitCast(v));
}

pub fn mov_m64_r64(self: *Self, base: R64, index: R64, scale: u8, r: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .X = reg_ex(index), .B = reg_ex(base) });
    try self.byte(0x89);
    if (base == R64.RBP) {
        try self.modrm_byte(.sib_disp8, r, .RSP);
        try self.sib_byte(base, index, scale);
        try self.byte(0x0);
    } else {
        try self.modrm_byte(.sib, r, .RSP);
        try self.sib_byte(base, index, scale);
    }
}

pub fn mov_r64_m64(self: *Self, r: R64, base: R64, index: R64, scale: u8) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .X = reg_ex(index), .B = reg_ex(base) });
    try self.byte(0x8B);
    if (base == R64.RBP) {
        try self.modrm_byte(.sib_disp8, r, .RSP);
        try self.sib_byte(base, index, scale);
        try self.byte(0x0);
    } else {
        try self.modrm_byte(.sib, r, .RSP);
        try self.sib_byte(base, index, scale);
    }
}

pub fn mov_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .B = reg_ex(p) });
    try self.byte(0x8B);
    try self.modrm_byte(.rm, r, p);
}

pub fn neg_r64(self: *Self, r: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r) });
    try self.byte(0xF7);
    try self.modrm_byte(.rm, @enumFromInt(0x3), r);
}

pub fn pop_r64(self: *Self, r: R64) !void {
    if (reg_ex(r)) {
        try self.rex_byte(.{ .B = true });
    }

    try self.op_reg_byte(0x58, r);
}

pub fn push_r64(self: *Self, r: R64) !void {
    if (reg_ex(r)) {
        try self.rex_byte(.{ .B = true });
    }

    try self.op_reg_byte(0x50, r);
}

pub fn push_imm32(self: *Self, v: u32) !void {
    try self.byte(0x68);
    try self.dword(v);
}

pub fn ret_near(self: *Self) !void {
    try self.byte(0xC3);
}

pub fn setcc_r8(self: *Self, r: R64, cc: u8) !void {
    if (reg_ex(r)) {
        try self.rex_byte(.{ .B = true });
    }
    try self.byte(0x0F);
    try self.byte(0x90 + cc);
    try self.modrm_byte(.rm, .RAX, r);
}

pub fn sub_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(p), .B = reg_ex(r) });
    try self.byte(0x29);
    try self.modrm_byte(.rm, p, r);
}

pub fn test_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(r), .B = reg_ex(p) });
    try self.byte(0x85);
    try self.modrm_byte(.rm, r, p);
}

pub fn xor_r64_r64(self: *Self, r: R64, p: R64) !void {
    try self.rex_byte(.{ .W = true, .R = reg_ex(p), .B = reg_ex(r) });
    try self.byte(0x31);
    try self.modrm_byte(.rm, p, r);
}
