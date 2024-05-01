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

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .as = As.init(alloc),
        .insn_map = std.ArrayList(usize).init(alloc),
        .relocs = std.ArrayList(Reloc).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.as.deinit();
    self.insn_map.deinit();
    self.relocs.deinit();
}

inline fn relocate(self: *Self, reloc: Reloc) void {
    const code = self.as.code();

    const val = switch (reloc.val) {
        .off => |off| off,
        .loc => |loc| self.insn_map.items[loc],
    };
    const off = val -% (reloc.off + 0x4);

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

fn syscall(v: i64) callconv(.C) void {
    const output_stream = std.io.getStdOut();
    const output_writer = output_stream.writer();

    output_writer.print("{}\n", .{v}) catch {};
}

pub fn compile(self: *Self, prog: arch.Program) !void {
    const as = &self.as;

    //try as.int3();
    try as.push_r64(.RBX);
    try as.push_r64(.RBP);
    try as.mov_r64_rm64(.RBP, .{ .reg = .RSP });
    try as.mov_r64_imm64(.RAX, -8);
    try as.add_r64_rm64(.RBP, .{ .reg = .RAX });
    try self.call_loc(prog.entry);
    try as.pop_r64(.RBP);
    try as.pop_r64(.RBX);
    try as.ret_near();

    for (prog.code) |i| {
        try self.insn_map.append(as.offset());

        switch (i.op) {
            .add => {
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.add_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.push_r64(.RAX);
            },
            .sub => {
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.sub_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.push_r64(.RAX);
            },
            .mul => {
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.imul_rm64(.{ .reg = .RBX });
                try as.push_r64(.RAX);
            },
            .mod => {
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cqo();
                try as.idiv_rm64(.{ .reg = .RBX });
                try as.push_r64(.RDX);
            },
            .inc => {
                try as.pop_r64(.RAX);
                try as.inc_rm64(.{ .reg = .RAX });
                try as.push_r64(.RAX);
            },
            .dec => {
                try as.pop_r64(.RAX);
                try as.dec_rm64(.{ .reg = .RAX });
                try as.push_r64(.RAX);
            },
            .dup => {
                try as.pop_r64(.RAX);
                try as.push_r64(.RAX);
                try as.push_r64(.RAX);
            },
            .stack_alloc => {
                try as.mov_r64_imm64(.RAX, i.operand.int * 8);
                try as.sub_r64_rm64(.RSP, .{ .reg = .RAX });
            },
            .cmp_lt => {
                try as.xor_r64_rm64(.RCX, .{ .reg = .RCX });
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cmp_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.setcc_rm8(.L, .{ .reg = .CL });
                try as.push_r64(.RCX);
            },
            .cmp_gt => {
                try as.xor_r64_rm64(.RCX, .{ .reg = .RCX });
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cmp_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.setcc_rm8(.G, .{ .reg = .CL });
                try as.push_r64(.RCX);
            },
            .cmp_eq => {
                try as.xor_r64_rm64(.RCX, .{ .reg = .RCX });
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cmp_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.setcc_rm8(.E, .{ .reg = .CL });
                try as.push_r64(.RCX);
            },
            .cmp_ne => {
                try as.xor_r64_rm64(.RCX, .{ .reg = .RCX });
                try as.pop_r64(.RBX);
                try as.pop_r64(.RAX);
                try as.cmp_r64_rm64(.RAX, .{ .reg = .RBX });
                try as.setcc_rm8(.NE, .{ .reg = .CL });
                try as.push_r64(.RCX);
            },
            .call => {
                try as.push_r64(.RBP);
                try as.mov_r64_rm64(.RBP, .{ .reg = .RSP });
                try as.mov_r64_imm64(.RAX, -8);
                try as.add_r64_rm64(.RBP, .{ .reg = .RAX });
                try self.call_loc(i.operand.location);
                try as.pop_r64(.RBP);
                try as.pop_r64(.RCX);
                try as.mov_r64_rm64(.RSI, .{ .reg = .RSP });
                try as.lea_r64(.RSI, .{ .base = .RSI, .index = .{ .reg = .RCX, .scale = 8 } });
                try as.mov_r64_rm64(.RSP, .{ .reg = .RSI });
                try as.push_r64(.RAX);
            },
            .syscall => {
                try as.mov_r64_imm64(.RAX, @bitCast(@intFromPtr(&syscall)));
                try as.pop_r64(.RDI);
                try as.mov_r64_imm64(.RBX, 0x8);
                try as.test_rm64_r64(.{ .reg = .RBX }, .RSP);
                const la = try self.jcc_lbl(.NE);
                try as.call_rm64(.{ .reg = .RAX });
                const lb = try self.jmp_lbl();
                self.put_lbl(la);
                try as.sub_r64_rm64(.RSP, .{ .reg = .RBX });
                try as.call_rm64(.{ .reg = .RAX });
                try as.add_r64_rm64(.RSP, .{ .reg = .RBX });
                self.put_lbl(lb);
            },
            .ret => {
                try as.pop_r64(.RAX);
                try as.mov_r64_rm64(.RSP, .{ .reg = .RBP });
                try as.ret_near();
            },
            .jmp => {
                try self.jmp_loc(i.operand.location);
            },
            .jmpnz => {
                try as.pop_r64(.RAX);
                try as.test_rm64_r64(.{ .reg = .RAX }, .RAX);
                try self.jcc_loc(.NE, i.operand.location);
            },
            .push => {
                try as.mov_r64_imm64(.RAX, i.operand.int);
                try as.push_r64(.RAX);
            },
            .load => {
                try as.mov_r64_imm64(.RCX, -i.operand.int - 1);
                try as.mov_r64_rm64(.RAX, .{ .mem = .{ .base = .RBP, .index = .{ .reg = .RCX, .scale = 8 } } });
                try as.push_r64(.RAX);
            },
            .store => {
                try as.pop_r64(.RAX);
                try as.mov_r64_imm64(.RCX, -i.operand.int - 1);
                try as.mov_rm64_r64(.{ .mem = .{ .base = .RBP, .index = .{ .reg = .RCX, .scale = 8 } } }, .RAX);
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

    const fun: ?*fn () callconv(.C) i64 = @ptrCast(ptr);
    const ret = fun.?();

    _ = std.os.linux.munmap(ptr.?, size);

    return ret;
}
