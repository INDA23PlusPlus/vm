const std = @import("std");

pub const CC = enum(u4) {
    O = 0x0, // Overflow
    NO = 0x1, // Not Overflow
    B = 0x2, // Below
    AE = 0x3, // Above or Equal
    E = 0x4, // Equal
    NE = 0x5, // Not Equal
    BE = 0x6, // Below or Equal
    A = 0x7, // Above
    S = 0x8, // Signed
    NS = 0x9, // Not Signed
    P = 0xA, // Parity
    NP = 0xB, // Not Parity
    L = 0xC, // Less
    GE = 0xD, // Greater or Equal
    LE = 0xE, // Less or Equal
    G = 0xF, // Greater

    pub inline fn negate(cc: CC) CC {
        return @enumFromInt(@intFromEnum(cc) ^ 1);
    }

    pub inline fn reverse(cc: CC) CC {
        return switch (cc) {
            .B, .AE, .BE, .A, .L, .GE, .LE, .G => negate(cc),
            else => cc,
        };
    }
};

pub const R8 = enum(u8) {
    AL = 0x0,
    CL = 0x1,
    DL = 0x2,
    BL = 0x3,
    AH = 0x4,
    CH = 0x5,
    DH = 0x6,
    BH = 0x7,
    R8L = 0x8,
    R9L = 0x9,
    R10L = 0xA,
    R11L = 0xB,
    R12L = 0xC,
    R13L = 0xD,
    R14L = 0xE,
    R15L = 0xF,
};

pub const R64 = enum(u8) {
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
    RIP,
};

pub const Mem = struct {
    base: ?R64 = null,
    index: ?struct {
        reg: R64,
        scale: u8,
    } = null,
    disp: i32 = 0,
};

pub const RM8 = union(enum) {
    reg: R8,
    mem: Mem,

    pub inline fn from(v: anytype) RM8 {
        return switch (@TypeOf(v)) {
            R8 => .{ .reg = v },
            Mem => .{ .mem = v },
            else => @compileError("Value is not convertible to RM64."),
        };
    }
};

pub const RM64 = union(enum) {
    reg: R64,
    mem: Mem,

    pub inline fn from(v: anytype) RM64 {
        return switch (@TypeOf(v)) {
            R64 => .{ .reg = v },
            Mem => .{ .mem = v },
            else => @compileError("Value is not convertible to RM64."),
        };
    }
};

const REX = struct {
    W: bool = false,
    R: bool = false,
    X: bool = false,
    B: bool = false,
};

const Mod = enum(u2) {
    mem = 0b00,
    mem_disp8 = 0b01,
    mem_disp32 = 0b10,
    reg = 0b11,
};

const ModRM = struct {
    mod: Mod = .mem,
    reg: u3 = 0,
    rm: u3 = 0,
};

const Disp = union(enum) {
    disp8: i8,
    disp32: i32,
};

const Imm = union(enum) {
    imm8: i8,
    imm16: i16,
    imm32: i32,
    imm64: i64,
};

const SIB = struct {
    scale: u2 = 0b00,
    index: u3 = 0b100,
    base: u3 = 0b101,
};

const OpcodeExt = union(enum) {
    r8: R8,
    r64: R64,
    cc: CC,
};

const Instr = struct {
    const Self = @This();

    rex: ?REX = null,
    esc: ?[]const u8 = null,
    opcode: u8 = 0,
    modrm: ?ModRM = null,
    sib: ?SIB = null,
    disp: ?Disp = null,
    imm: ?Imm = null,

    pub inline fn set_rex(self: *Self, rex: REX) void {
        self.rex = rex;
    }

    pub inline fn set_esc(self: *Self, esc: []const u8) void {
        self.esc = esc;
    }

    pub inline fn set_opcode(self: *Self, opcode: u8, ext: ?OpcodeExt) void {
        if (ext != null) {
            switch (ext.?) {
                inline .r8, .r64 => |reg| {
                    if (@intFromEnum(reg) >= 0x10) {
                        @panic("Invalid register.");
                    } else if (@intFromEnum(reg) >= 0x8) {
                        if (self.rex) |*rex| {
                            rex.B = true;
                        } else {
                            self.rex = .{ .B = true };
                        }
                    } else {
                        if (self.rex) |*rex| {
                            rex.B = false;
                        }
                    }
                    self.opcode = opcode + @as(u3, @truncate(@intFromEnum(reg)));
                },
                .cc => |cc| {
                    self.opcode = opcode + @intFromEnum(cc);
                },
            }
        } else {
            self.opcode = opcode;
        }
    }

    pub inline fn set_modrm_mod(self: *Self, mod: Mod) void {
        if (self.modrm) |*modrm| {
            modrm.mod = mod;
        } else {
            self.modrm = .{ .mod = mod };
        }
    }

    pub inline fn set_modrm_ext(self: *Self, ext: u3) void {
        if (self.modrm) |*modrm| {
            modrm.reg = ext;
        } else {
            self.modrm = .{ .reg = ext };
        }
    }

    pub inline fn set_modrm_reg(self: *Self, reg: anytype) void {
        if (@intFromEnum(reg) >= 0x10) {
            @panic("Invalid register.");
        } else if (@intFromEnum(reg) >= 0x8) {
            if (self.rex) |*rex| {
                rex.R = true;
            } else {
                self.rex = .{ .R = true };
            }
        } else {
            if (self.rex) |*rex| {
                rex.R = false;
            }
        }

        if (self.modrm) |*modrm| {
            modrm.reg = @truncate(@intFromEnum(reg));
        } else {
            self.modrm = .{ .reg = @truncate(@intFromEnum(reg)) };
        }
    }

    pub inline fn set_modrm_rm(self: *Self, reg: anytype) void {
        comptime switch (@TypeOf(reg)) {
            R8, R64 => {},
            else => @compileError("Incompatible type for reg."),
        };

        if (@intFromEnum(reg) >= 0x10) {
            @panic("Invalid register.");
        } else if (@intFromEnum(reg) >= 0x8) {
            if (self.rex) |*rex| {
                rex.B = true;
            } else {
                self.rex = .{ .B = true };
            }
        } else {
            if (self.rex) |*rex| {
                rex.B = false;
            }
        }

        if (self.modrm) |*modrm| {
            modrm.rm = @truncate(@intFromEnum(reg));
        } else {
            self.modrm = .{ .rm = @truncate(@intFromEnum(reg)) };
        }
    }

    pub inline fn set_sib_base(self: *Self, reg: R64) void {
        if (@intFromEnum(reg) >= 0x10) {
            @panic("Invalid register.");
        } else if (@intFromEnum(reg) >= 0x8) {
            if (self.rex) |*rex| {
                rex.B = true;
            } else {
                self.rex = .{ .B = true };
            }
        } else {
            if (self.rex) |*rex| {
                rex.B = false;
            }
        }

        if (self.sib) |*sib| {
            sib.base = @truncate(@intFromEnum(reg));
        } else {
            self.sib = .{ .base = @truncate(@intFromEnum(reg)) };
        }
    }

    pub inline fn set_sib_index(self: *Self, reg: R64, scale: u8) void {
        const sib_scale: u2 = switch (scale) {
            1 => 0b00,
            2 => 0b01,
            4 => 0b10,
            8 => 0b11,
            else => {
                @panic("Invalid scale for memory index.");
            },
        };

        if (@intFromEnum(reg) >= 0x10) {
            @panic("Invalid register.");
        } else if (@intFromEnum(reg) >= 0x8) {
            if (self.rex) |*rex| {
                rex.X = true;
            } else {
                self.rex = .{ .X = true };
            }
        } else {
            if (self.rex) |*rex| {
                rex.X = false;
            }
        }

        if (self.sib) |*sib| {
            sib.scale = sib_scale;
            sib.index = @truncate(@intFromEnum(reg));
        } else {
            self.sib = .{ .scale = sib_scale, .index = @truncate(@intFromEnum(reg)) };
        }
    }

    pub inline fn set_rm_reg(self: *Self, reg: anytype) void {
        self.set_modrm_mod(.reg);
        self.set_modrm_rm(reg);
    }

    pub inline fn set_rm_mem(self: *Self, mem: Mem) void {
        var disp_min: usize = 0;

        if (mem.disp < std.math.minInt(i8) or mem.disp > std.math.maxInt(i8)) {
            disp_min = 4;
        } else if (mem.disp != 0) {
            disp_min = 1;
        }

        if (mem.base == null) {
            if (mem.index) |index| {
                switch (index.reg) {
                    .RAX, .RCX, .RDX, .RBX, .RSI, .RDI, .R8, .R9, .R10, .R11, .R12, .R14, .R15 => {
                        self.set_modrm_mod(.mem);
                        self.set_modrm_rm(R64.RSP);
                        self.set_sib_index(index.reg, index.scale);
                        self.set_sib_base(R64.RBP);
                        self.disp = .{ .disp32 = mem.disp };
                        return;
                    },
                    else => {},
                }
            } else {
                self.set_modrm_mod(.mem);
                self.set_modrm_rm(R64.RSP);
                self.set_sib_index(.RSP, 1);
                self.set_sib_base(.RBP);
                self.disp = .{ .disp32 = mem.disp };
                return;
            }
        } else if (mem.index == null) {
            if (mem.base) |base| {
                switch (base) {
                    .RAX, .RCX, .RDX, .RBX, .RSI, .RDI, .R8, .R9, .R10, .R11, .R14, .R15 => {
                        if (disp_min == 4) {
                            self.set_modrm_mod(.mem_disp32);
                            self.disp = .{ .disp32 = @intCast(mem.disp) };
                        } else if (disp_min == 1) {
                            self.set_modrm_mod(.mem_disp8);
                            self.disp = .{ .disp8 = @intCast(mem.disp) };
                        } else {
                            self.set_modrm_mod(.mem);
                            self.disp = null;
                        }
                        self.set_modrm_rm(base);
                        self.sib = null;
                        return;
                    },
                    .RSP, .R12 => {
                        if (disp_min == 4) {
                            self.set_modrm_mod(.mem_disp32);
                            self.disp = .{ .disp32 = @intCast(mem.disp) };
                        } else if (disp_min == 1) {
                            self.set_modrm_mod(.mem_disp8);
                            self.disp = .{ .disp8 = @intCast(mem.disp) };
                        } else {
                            self.set_modrm_mod(.mem);
                            self.disp = null;
                        }
                        self.set_modrm_rm(R64.RSP);
                        self.set_sib_base(base);
                        self.set_sib_index(.RSP, 1);
                        return;
                    },
                    .RBP, .R13 => {
                        if (disp_min == 4) {
                            self.set_modrm_mod(.mem_disp32);
                            self.disp = .{ .disp32 = @intCast(mem.disp) };
                        } else {
                            self.set_modrm_mod(.mem_disp8);
                            self.disp = .{ .disp8 = @intCast(mem.disp) };
                        }
                        self.set_modrm_rm(base);
                        self.sib = null;
                        return;
                    },
                    .RIP => {
                        self.set_modrm_mod(.mem);
                        self.set_modrm_rm(R64.RBP);
                        self.sib = null;
                        self.disp = .{ .disp32 = mem.disp };
                        return;
                    },
                }
            }
        } else {
            switch (mem.base.?) {
                .RAX, .RCX, .RDX, .RBX, .RSP, .RSI, .RDI, .R8, .R9, .R10, .R11, .R12, .R14, .R15 => {
                    if (disp_min == 4) {
                        self.set_modrm_mod(.mem_disp32);
                        self.disp = .{ .disp32 = @intCast(mem.disp) };
                    } else if (disp_min == 1) {
                        self.set_modrm_mod(.mem_disp8);
                        self.disp = .{ .disp8 = @intCast(mem.disp) };
                    } else {
                        self.set_modrm_mod(.mem);
                        self.disp = null;
                    }
                    self.set_modrm_rm(R64.RSP);
                    self.set_sib_base(mem.base.?);
                    self.set_sib_index(mem.index.?.reg, mem.index.?.scale);
                    return;
                },
                .RBP, .R13 => {
                    if (disp_min == 4) {
                        self.set_modrm_mod(.mem_disp32);
                        self.disp = .{ .disp32 = @intCast(mem.disp) };
                    } else {
                        self.set_modrm_mod(.mem_disp8);
                        self.disp = .{ .disp8 = @intCast(mem.disp) };
                    }
                    self.set_modrm_rm(R64.RSP);
                    self.set_sib_base(mem.base.?);
                    self.set_sib_index(mem.index.?.reg, mem.index.?.scale);
                    return;
                },
                else => {},
            }
        }

        @panic("Invalid memory operand.");
    }

    pub inline fn set_rm(self: *Self, rm: anytype) void {
        comptime switch (@TypeOf(rm)) {
            RM8, RM64 => {},
            else => @compileError("Incompatible type for rm."),
        };

        switch (rm) {
            .reg => |reg| {
                self.set_rm_reg(reg);
            },
            .mem => |mem| {
                self.set_rm_mem(mem);
            },
        }
    }

    pub inline fn set_imm(self: *Self, imm: Imm) void {
        self.imm = imm;
    }
};

pub const As = struct {
    const Self = @This();

    code_array: std.ArrayList(u8),
    disp_off: usize,
    imm_off: usize,

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .code_array = std.ArrayList(u8).init(alloc),
            .disp_off = 0,
            .imm_off = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.code_array.deinit();
    }

    pub fn reset(self: *Self) void {
        self.code_array.clearRetainingCapacity();
    }

    pub inline fn code(self: *Self) []u8 {
        return self.code_array.items;
    }

    pub inline fn offset(self: *Self) usize {
        return self.code().len;
    }

    inline fn put_byte(self: *Self, byte: u8) !void {
        try self.code_array.append(byte);
    }

    inline fn put_bytes(self: *Self, bytes: []const u8) !void {
        try self.code_array.appendSlice(bytes);
    }

    inline fn put_word(self: *Self, word: u16) !void {
        const bytes = [_]u8{
            @truncate(word >> 0),
            @truncate(word >> 8),
        };
        try self.put_bytes(&bytes);
    }

    inline fn put_dword(self: *Self, dword: u32) !void {
        const bytes = [_]u8{
            @truncate(dword >> 0),
            @truncate(dword >> 8),
            @truncate(dword >> 16),
            @truncate(dword >> 24),
        };
        try self.put_bytes(&bytes);
    }

    inline fn put_qword(self: *Self, qword: u64) !void {
        const bytes = [_]u8{
            @truncate(qword >> 0),
            @truncate(qword >> 8),
            @truncate(qword >> 16),
            @truncate(qword >> 24),
            @truncate(qword >> 32),
            @truncate(qword >> 40),
            @truncate(qword >> 48),
            @truncate(qword >> 56),
        };
        try self.put_bytes(&bytes);
    }

    inline fn emit_instr(self: *Self, instr: Instr) !void {
        @setEvalBranchQuota(8000);

        if (instr.rex) |rex| {
            var rex_byte: u8 = 0x40;

            if (rex.W) {
                rex_byte |= 0x08;
            }
            if (rex.R) {
                rex_byte |= 0x04;
            }
            if (rex.X) {
                rex_byte |= 0x02;
            }
            if (rex.B) {
                rex_byte |= 0x01;
            }

            try self.put_byte(rex_byte);
        }

        if (instr.esc) |esc| {
            try self.put_bytes(esc);
        }

        try self.put_byte(instr.opcode);

        if (instr.modrm) |modrm| {
            var modrm_byte: u8 = 0;

            modrm_byte |= @as(u8, @intCast(@intFromEnum(modrm.mod))) << 6;
            modrm_byte |= @as(u8, @intCast(modrm.reg)) << 3;
            modrm_byte |= @as(u8, @intCast(modrm.rm)) << 0;

            try self.put_byte(modrm_byte);
        }

        if (instr.sib) |sib| {
            var sib_byte: u8 = 0;

            sib_byte |= @as(u8, @intCast(sib.scale)) << 6;
            sib_byte |= @as(u8, @intCast(sib.index)) << 3;
            sib_byte |= @as(u8, @intCast(sib.base)) << 0;

            try self.put_byte(sib_byte);
        }

        if (instr.disp) |disp| {
            self.disp_off = self.offset();

            switch (disp) {
                .disp8 => |disp8| {
                    try self.put_byte(@bitCast(disp8));
                },
                .disp32 => |disp32| {
                    try self.put_dword(@bitCast(disp32));
                },
            }
        }

        if (instr.imm) |imm| {
            self.imm_off = self.offset();

            switch (imm) {
                .imm8 => |imm8| {
                    try self.put_byte(@bitCast(imm8));
                },
                .imm16 => |imm16| {
                    try self.put_word(@bitCast(imm16));
                },
                .imm32 => |imm32| {
                    try self.put_dword(@bitCast(imm32));
                },
                .imm64 => |imm64| {
                    try self.put_qword(@bitCast(imm64));
                },
            }
        }
    }

    pub inline fn add_r64_rm64(self: *Self, reg: R64, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x03, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn add_rm64_imm8(self: *Self, rm: RM64, imm: i8) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x83, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm8 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn add_rm64_imm32(self: *Self, rm: RM64, imm: i32) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x81, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn add_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x01, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn and_rm64_imm8(self: *Self, rm: RM64, imm: i8) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x83, null);
        instr.set_modrm_ext(4);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm8 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn call_rel32(self: *Self, rel: i32) !void {
        var instr = Instr{};
        instr.set_opcode(0xE8, null);
        instr.set_imm(.{ .imm32 = rel });
        try self.emit_instr(instr);
    }

    pub inline fn call_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_opcode(0xFF, null);
        instr.set_modrm_ext(2);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn cmp_r64_rm64(self: *Self, reg: R64, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x3B, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn cmp_rm64_imm32(self: *Self, rm: RM64, imm: i32) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x81, null);
        instr.set_modrm_ext(7);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn cmp_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x39, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn cqo(self: *Self) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x99, null);
        try self.emit_instr(instr);
    }

    pub inline fn dec_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xFF, null);
        instr.set_modrm_ext(1);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn inc_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xFF, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn idiv_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xF7, null);
        instr.set_modrm_ext(7);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn imul_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xF7, null);
        instr.set_modrm_ext(5);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn int3(self: *Self) !void {
        var instr = Instr{};
        instr.set_opcode(0xCC, null);
        try self.emit_instr(instr);
    }

    pub inline fn jcc_rel32(self: *Self, cc: CC, rel: i32) !void {
        var instr = Instr{};
        instr.set_esc(&.{0x0F});
        instr.set_opcode(0x80, .{ .cc = cc });
        instr.set_imm(.{ .imm32 = rel });
        try self.emit_instr(instr);
    }

    pub inline fn jmp_rel32(self: *Self, rel: i32) !void {
        var instr = Instr{};
        instr.set_opcode(0xE9, null);
        instr.set_imm(.{ .imm32 = rel });
        try self.emit_instr(instr);
    }

    pub inline fn lea_r64(self: *Self, reg: R64, mem: Mem) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x8D, null);
        instr.set_modrm_reg(reg);
        instr.set_rm_mem(mem);
        try self.emit_instr(instr);
    }

    pub inline fn mov_r64_imm64(self: *Self, reg: R64, imm: i64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xB8, .{ .r64 = reg });
        instr.set_imm(.{ .imm64 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn mov_r64_rm64(self: *Self, reg: R64, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x8B, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn mov_rm64_imm32(self: *Self, rm: RM64, imm: i32) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xC7, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn mov_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x89, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn movsq(self: *Self) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xA5, null);
        try self.emit_instr(instr);
    }

    pub inline fn movzx_r64_rm8(self: *Self, reg: R64, rm: RM8) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_esc(&.{0x0F});
        instr.set_opcode(0xB6, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn neg_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xF7, null);
        instr.set_modrm_ext(3);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn pop_r64(self: *Self, reg: R64) !void {
        var instr = Instr{};
        instr.set_opcode(0x58, .{ .r64 = reg });
        try self.emit_instr(instr);
    }

    pub inline fn pop_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_opcode(0x8F, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn push_r64(self: *Self, reg: R64) !void {
        var instr = Instr{};
        instr.set_opcode(0x50, .{ .r64 = reg });
        try self.emit_instr(instr);
    }

    pub inline fn push_rm64(self: *Self, rm: RM64) !void {
        var instr = Instr{};
        instr.set_opcode(0xFF, null);
        instr.set_modrm_ext(6);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn push_imm8(self: *Self, imm: i8) !void {
        var instr = Instr{};
        instr.set_opcode(0x6A, null);
        instr.set_imm(.{ .imm8 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn push_imm32(self: *Self, imm: i32) !void {
        var instr = Instr{};
        instr.set_opcode(0x68, null);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn rep(self: *Self) !void {
        var instr = Instr{};
        instr.set_opcode(0xF3, null);
        try self.emit_instr(instr);
    }

    pub inline fn ret_near(self: *Self) !void {
        var instr = Instr{};
        instr.set_opcode(0xC3, null);
        try self.emit_instr(instr);
    }

    pub inline fn setcc_rm8(self: *Self, cc: CC, rm: RM8) !void {
        var instr = Instr{};
        instr.set_esc(&.{0x0F});
        instr.set_opcode(0x90, .{ .cc = cc });
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn std_(self: *Self) !void {
        var instr = Instr{};
        instr.set_opcode(0xFD, null);
        try self.emit_instr(instr);
    }

    pub inline fn sub_r64_rm64(self: *Self, reg: R64, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x2B, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn sub_rm64_imm8(self: *Self, rm: RM64, imm: i8) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x83, null);
        instr.set_modrm_ext(5);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm8 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn sub_rm64_imm32(self: *Self, rm: RM64, imm: i32) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x81, null);
        instr.set_modrm_ext(5);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn sub_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x29, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn test_rm64_imm32(self: *Self, rm: RM64, imm: i32) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0xF7, null);
        instr.set_modrm_ext(0);
        instr.set_rm(rm);
        instr.set_imm(.{ .imm32 = imm });
        try self.emit_instr(instr);
    }

    pub inline fn test_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x85, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn xchg_rm64_r64(self: *Self, rm: RM64, reg: R64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x87, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }

    pub inline fn xor_r64_rm64(self: *Self, reg: R64, rm: RM64) !void {
        var instr = Instr{};
        instr.set_rex(.{ .W = true });
        instr.set_opcode(0x33, null);
        instr.set_modrm_reg(reg);
        instr.set_rm(rm);
        try self.emit_instr(instr);
    }
};

test "instruction encodings" {
    var as = As.init(std.testing.allocator);
    defer as.deinit();

    try as.add_r64_rm64(.RAX, .{ .mem = .{ .base = .RBX, .index = .{ .reg = .RBP, .scale = 2 } } });
    try as.sub_r64_rm64(.RAX, .{ .mem = .{ .base = .RBX, .index = .{ .reg = .RBP, .scale = 2 } } });
    try as.call_rel32(4);
    try as.call_rm64(.{ .reg = .RAX });
    try as.mov_r64_imm64(.R12, 23);
    try as.lea_r64(.R12, .{ .base = .RSP });
    try as.cmp_r64_rm64(.R12, .{ .reg = .RAX });
    try as.dec_rm64(.{ .reg = .RAX });
    try as.jcc_rel32(.GE, 33);
    try as.mov_r64_rm64(.RCX, .{ .mem = .{ .base = .RSP, .disp = 8 } });
    try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP, .disp = 8 } }, .RCX);
    try as.neg_rm64(.{ .reg = .RSP });
    try as.pop_r64(.R15);
    try as.push_r64(.R14);
    try as.push_imm32(111);
    try as.setcc_rm8(.NP, .{ .reg = .AH });
    try as.test_rm64_r64(.{ .reg = .RCX }, .RDX);
    try as.xor_r64_rm64(.RDX, .{ .reg = .RCX });

    const expected = [_]u8{ 0x48, 0x03, 0x04, 0x6b, 0x48, 0x2b, 0x04, 0x6b, 0xe8, 0x04, 0x00, 0x00, 0x00, 0xff, 0xd0, 0x49, 0xbc, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4c, 0x8d, 0x24, 0x24, 0x4c, 0x3b, 0xe0, 0x48, 0xff, 0xc8, 0x0f, 0x8d, 0x21, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x4c, 0x24, 0x08, 0x48, 0x89, 0x4c, 0x24, 0x08, 0x48, 0xf7, 0xdc, 0x41, 0x5f, 0x41, 0x56, 0x68, 0x6f, 0x00, 0x00, 0x00, 0x0f, 0x9b, 0xc4, 0x48, 0x85, 0xd1, 0x48, 0x33, 0xd1 };
    try std.testing.expectEqualSlices(u8, &expected, as.code());

    if (false) {
        var first = true;
        for (as.code()) |b| {
            if (first) {
                std.debug.print("0x{x:0>2}", .{b});
                first = false;
            } else {
                std.debug.print(", 0x{x:0>2}", .{b});
            }
        }
        std.debug.print("\n", .{});
    }
}
