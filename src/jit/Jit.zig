const std = @import("std");
const arch = @import("arch");
const As = @import("as.zig").As;
const CC = @import("as.zig").CC;

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

as: As,
insn_map: std.ArrayList(usize),
relocs: std.ArrayList(Reloc),
dbgjit: ?[]const u8,

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .as = As.init(alloc),
        .insn_map = std.ArrayList(usize).init(alloc),
        .relocs = std.ArrayList(Reloc).init(alloc),
        .dbgjit = std.posix.getenv("DBGJIT"),
    };
}

pub fn deinit(self: *Self) void {
    self.as.deinit();
    self.insn_map.deinit();
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
        .loc => |loc| self.insn_map.items[loc],
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

inline fn jcc_loc(self: *Self, cc: CC, loc: usize) !void {
    try self.as.jcc_rel32(cc, 0);
    try self.relocs.append(.{ .off = self.as.imm_off, .val = .{ .loc = loc } });
}

inline fn jcc_lbl(self: *Self, cc: CC) !Lbl {
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
    var output_stream: std.fs.File = undefined;
    var output_writer: std.fs.File.Writer = undefined;

    inline fn init() void {
        output_stream = std.io.getStdOut();
        output_writer = output_stream.writer();
    }
};

fn syscall(v: i64) callconv(.C) void {
    exec_globals.output_writer.print("{}\n", .{v}) catch {};
}

pub fn compile(self: *Self, prog: arch.Program) !void {
    const as = &self.as;

    try self.dbg_break("start");
    try as.push_r64(.RBX);
    try as.push_r64(.RBP);
    try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
    try self.call_loc(prog.entry);
    try self.dbg_break("end");
    try as.pop_r64(.RBP);
    try as.pop_r64(.RBX);
    try as.ret_near();

    for (prog.code) |i| {
        try self.insn_map.append(as.offset());

        switch (i.op) {
            .add => {
                try self.dbg_break("add");
                try as.pop_r64(.RAX);
                try as.add_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .sub => {
                try self.dbg_break("sub");
                try as.pop_r64(.RAX);
                try as.sub_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .mul => {
                try self.dbg_break("mul");
                try as.pop_r64(.RAX);
                try as.imul_rm64(.{ .mem = .{ .base = .RSP } });
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .mod => {
                try self.dbg_break("mod");
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cqo();
                try as.idiv_rm64(.{ .reg = .RBX });
                try as.push_r64(.RDX);
            },
            .inc => {
                try self.dbg_break("inc");
                try as.inc_rm64(.{ .mem = .{ .base = .RSP } });
            },
            .dec => {
                try self.dbg_break("dec");
                try as.dec_rm64(.{ .mem = .{ .base = .RSP } });
            },
            .dup => {
                try self.dbg_break("dup");
                try as.push_rm64(.{ .mem = .{ .base = .RSP } });
            },
            .stack_alloc => {
                try self.dbg_break("stack_alloc");
                try as.sub_rm64_imm32(.{ .reg = .RSP }, @truncate(i.operand.int * 8));
            },
            .cmp_lt => {
                try self.dbg_break("cmp_lt");
                try as.pop_r64(.RAX);
                try as.cmp_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
                try as.setcc_rm8(.L, .{ .reg = .AL });
                try as.movzx_r64_rm8(.RAX, .{ .reg = .AL });
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .cmp_gt => {
                try self.dbg_break("cmp_gt");
                try as.pop_r64(.RAX);
                try as.cmp_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
                try as.setcc_rm8(.G, .{ .reg = .AL });
                try as.movzx_r64_rm8(.RAX, .{ .reg = .AL });
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .cmp_eq => {
                try self.dbg_break("cmp_eq");
                try as.pop_r64(.RAX);
                try as.cmp_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
                try as.setcc_rm8(.E, .{ .reg = .AL });
                try as.movzx_r64_rm8(.RAX, .{ .reg = .AL });
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .cmp_ne => {
                try self.dbg_break("cmp_ne");
                try as.pop_r64(.RAX);
                try as.cmp_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
                try as.setcc_rm8(.NE, .{ .reg = .AL });
                try as.movzx_r64_rm8(.RAX, .{ .reg = .AL });
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RSP } }, .RAX);
            },
            .call => {
                try self.dbg_break("call");
                try as.push_r64(.RBP);
                try as.lea_r64(.RBP, .{ .base = .RSP, .disp = -8 });
                try self.call_loc(i.operand.location);
                try self.dbg_break("call_ret");
                try as.pop_r64(.RBP);
                try as.pop_r64(.RCX);
                try as.lea_r64(.RSP, .{ .base = .RSP, .index = .{ .reg = .RCX, .scale = 8 } });
                try as.push_r64(.RAX);
            },
            .syscall => {
                try self.dbg_break("syscall");
                switch (i.operand.int) {
                    0 => {
                        try as.mov_r64_rm64(.RDI, .{ .mem = .{ .base = .RSP } });
                        try as.mov_r64_imm64(.RAX, @bitCast(@intFromPtr(&syscall)));
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
                try self.dbg_break("ret");
                try as.pop_r64(.RAX);
                try as.mov_r64_rm64(.RSP, .{ .reg = .RBP });
                try as.ret_near();
            },
            .jmp => {
                try self.dbg_break("jmp");
                try self.jmp_loc(i.operand.location);
            },
            .jmpnz => {
                try self.dbg_break("jmpnz");
                try as.pop_r64(.RAX);
                try as.test_rm64_r64(.{ .reg = .RAX }, .RAX);
                try self.jcc_loc(.NE, i.operand.location);
            },
            .push => {
                try self.dbg_break("push");
                if (imm_size(i.operand.int) <= 4) {
                    try as.push_imm32(@truncate(i.operand.int));
                } else {
                    try as.mov_r64_imm64(.RAX, i.operand.int);
                    try as.push_r64(.RAX);
                }
            },
            .pop => {
                try self.dbg_break("pop");
                try as.add_rm64_imm8(.{ .reg = .RSP }, 8);
            },
            .load => {
                try self.dbg_break("load");
                try as.push_rm64(.{ .mem = .{ .base = .RBP, .disp = @truncate((-i.operand.int - 1) * 8) } });
            },
            .store => {
                try self.dbg_break("store");
                try as.pop_r64(.RAX);
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RBP, .disp = @truncate((-i.operand.int - 1) * 8) } }, .RAX);
            },
            else => {
                std.debug.print("Unimplemented instruction: {s}.\n", .{@tagName(i.op)});
            },
        }
    }

    self.relocate_all();
}

pub fn execute(self: *Self) !i64 {
    const code = self.as.code();
    const size = self.as.offset();

    // PROT_READ | PROT_WRITE
    const addr = std.os.linux.mmap(null, size, 0x1 | 0x2, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr: ?[*]u8 = @ptrFromInt(addr);

    if (ptr == null) {
        return error.OutOfMemory;
    }

    @memcpy(ptr.?, code);

    // PROT_READ | PROT_EXEC
    if (std.os.linux.mprotect(ptr.?, size, 0x1 | 0x4) != 0) {
        return error.AccessDenied;
    }

    exec_globals.init();

    const fun: ?*fn () callconv(.C) i64 = @ptrCast(ptr);
    const ret = fun.?();

    _ = std.os.linux.munmap(ptr.?, size);

    return ret;
}
