//!
//! The intermediate language assembler.
//!
//! Initialize with Asm.init, which takes a pointer to
//! a std.ArrayList(Error).
//! Use Asm.assemble to assemble the code.
//! Check for errors by checking length of error list.
//! Assembled program is accessed through Asm.getCode.
//!

const Asm = @This();
const std = @import("std");
const vm = @import("vm");
const Patcher = @import("Patcher.zig");
const Error = @import("Error.zig");
const Token = @import("Token.zig");
const Scanner = Token.Scanner;
const Instruction = @import("instr").Instruction;
const emit_ = @import("emit.zig");

code: std.ArrayList(vm.VMInstruction),
scan: Scanner,
fn_patcher: Patcher,
lbl_patcher: Patcher,
errors: *std.ArrayList(Error),

pub fn init(
    source: []const u8,
    allocator: std.mem.Allocator,
    errors: *std.ArrayList(Error),
) Asm {
    return .{
        .code = std.ArrayList(vm.VMInstruction).init(allocator),
        .scan = .{ .source = source, .errors = errors },
        .fn_patcher = Patcher.init(allocator, errors),
        .lbl_patcher = Patcher.init(allocator, errors),
        .errors = errors,
    };
}

pub fn deinit(self: *Asm) void {
    self.code.deinit();
    self.fn_patcher.deinit();
    self.lbl_patcher.deinit();
}

pub fn getCode(self: *Asm) []const vm.VMInstruction {
    return self.code.items;
}

pub fn assemble(self: *Asm) !void {
    while (try self.scan.peek()) |_| {
        self.asmFunc() catch |err| {
            if (err == std.mem.Allocator.Error.OutOfMemory) {
                return err;
            } else {
                try syncUntilNextFunc(self);
            }
        };
    }
    try self.fn_patcher.patch(self.code.items);
}

pub fn emit(self: *Asm, writer: anytype) !void {
    try emit_.emit(self, writer);
}

fn asmFunc(self: *Asm) !void {
    _ = try self.expectKw(.function, "expected 'function'");
    const name = try self.expect(.string, "expected function name");
    _ = try self.expectKw(.begin, "expected 'begin'");
    try self.fn_patcher.decl(name.where, self.code.items.len);
    self.lbl_patcher.reset();
    while (try self.scan.peek()) |tok| {
        switch (tok.tag) {
            .label => try self.asmLabel(),
            .instr => try self.asmInstr(),
            else => {
                _ = try self.expectKw(.end, "expected 'end'");
                break;
            },
        }
    }
    try self.lbl_patcher.patch(self.code.items);
    self.lbl_patcher.reset();
}

fn asmInstr(self: *Asm) !void {
    const instr = try self.expect(.instr, null);
    const offset = self.code.items.len;
    try self.code.append(.{
        .op = instr.tag.instr,
    });

    if (instr.tag.instr.hasOperand()) {
        switch (instr.tag.instr) {
            .call => {
                const func = try self.expect(.string, "expected function name");
                try self.fn_patcher.reference(func.where, offset);
            },
            .jmp, .jmpnz => {
                const lbl = try self.expect(.label, "expected label");
                try self.lbl_patcher.reference(lbl.where, offset);
            },
            else => {
                const immed = try self.expect(.immed, "expected operand");
                self.code.items[offset].operand = .{
                    .int = immed.tag.immed,
                };
            },
        }
    }
}

fn asmLabel(self: *Asm) !void {
    const lbl = try self.expect(.label, null);
    try self.lbl_patcher.decl(lbl.where, self.code.items.len);
}

fn getToken(self: *Asm, extra: ?[]const u8) !Token {
    return try self.scan.next() orelse {
        try self.errors.append(.{
            .tag = .unexpected_eof,
            .where = self.scan.source[self.scan.source.len - 1 ..],
            .extra = extra,
        });
        return error.UnexpectedEOF;
    };
}

fn expect(self: *Asm, tag: std.meta.Tag(Token.Tag), extra: ?[]const u8) !Token {
    const tok = try self.getToken(extra);
    if (tok.tag != tag) {
        try self.errors.append(.{
            .tag = .unexpected_token,
            .where = tok.where,
            .extra = extra,
        });
        return error.UnexpectedToken;
    }
    return tok;
}

fn expectKw(self: *Asm, kw: Token.Keyword, extra: ?[]const u8) !Token {
    const tok = try self.expect(.keyword, extra);
    if (tok.tag.keyword != kw) {
        try self.errors.append(.{
            .tag = .unexpected_token,
            .where = tok.where,
            .extra = extra,
        });
        return error.UnexpectedToken;
    }
    return tok;
}

fn syncUntilNextFunc(self: *Asm) !void {
    while (try self.scan.peek()) |tok| {
        if (tok.tag == .keyword and tok.tag.keyword == .function) break;
        _ = try self.scan.next();
    }
}

fn syncUntilNextStmt(self: *Asm) !void {
    while (try self.scan.peek()) |tok| {
        if (tok.tag == .instr) break;
        _ = try self.scan.next();
    }
}
