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
const arch = @import("arch");
const Instruction = arch.Instruction;
const Program = arch.Program;
const Patcher = @import("Patcher.zig");
const Error = @import("Error.zig");
const Token = @import("Token.zig");
const Scanner = Token.Scanner;
const StringPool = @import("StringPool.zig");
const StringParser = @import("StringParser.zig");

const entry_name = "main";

code: std.ArrayList(Instruction),
entry: ?usize,
scan: Scanner,
fn_patcher: Patcher,
lbl_patcher: Patcher,
str_patcher: Patcher,
string_pool: StringPool,
field_name_pool: StringPool,
errors: *std.ArrayList(Error),
str_build: std.ArrayList(u8),
str_parser: StringParser,

pub fn init(
    source: []const u8,
    allocator: std.mem.Allocator,
    errors: *std.ArrayList(Error),
) Asm {
    return .{
        .code = std.ArrayList(Instruction).init(allocator),
        .scan = .{ .source = source, .errors = errors },
        .fn_patcher = Patcher.init(allocator, errors),
        .lbl_patcher = Patcher.init(allocator, errors),
        .str_patcher = Patcher.init(allocator, errors),
        .string_pool = StringPool.init(allocator),
        .field_name_pool = StringPool.init(allocator),
        .errors = errors,
        .entry = null,
        .str_build = std.ArrayList(u8).init(allocator),
        .str_parser = StringParser.init(allocator, errors),
    };
}

pub fn deinit(self: *Asm) void {
    self.code.deinit();
    self.fn_patcher.deinit();
    self.lbl_patcher.deinit();
    self.str_patcher.deinit();
    self.string_pool.deinit();
    self.field_name_pool.deinit();
    self.str_build.deinit();
    self.str_parser.deinit();
}

pub fn assemble(self: *Asm) !void {
    while (try self.scan.peek()) |leading| {
        if (leading.tag != .keyword) {
            try self.errors.append(.{
                .where = leading.where,
                .tag = .@"Unexpected token",
                .extra = "expected '-string' or '-function'",
            });
            try self.syncUntilNextToplevel();
            continue;
        }

        const result = switch (leading.tag.keyword) {
            .function => self.asmFunc(),
            .string => self.asmString(),
            else => {
                try self.errors.append(.{
                    .where = leading.where,
                    .tag = .@"Unexpected token",
                    .extra = "expected '-string' or '-function'",
                });
                try self.syncUntilNextToplevel();
                continue;
            },
        };

        _ = result catch |err| {
            if (err == std.mem.Allocator.Error.OutOfMemory) {
                return err;
            } else {
                try syncUntilNextToplevel(self);
            }
        };
    }

    try self.fn_patcher.patch(self.code.items);
    try self.str_patcher.patch(self.code.items);

    if (self.entry == null) {
        try self.errors.append(.{
            .tag = .@"No main function",
        });
    }
}

/// Copies relevant data and constructs a VM program.
pub fn getProgram(self: *Asm, allocator: std.mem.Allocator) !Program {
    const code = try allocator.dupe(Instruction, self.code.items);

    // This assumes there were no assembler errors,
    // i.e. the main funciton exists.
    const entry = self.entry.?;

    const num_strings = self.string_pool.entries.items.len;
    const string_buffer = try allocator.dupe(u8, self.string_pool.getContiguous());
    var strings = try allocator.alloc([]const u8, num_strings);

    for (0.., self.string_pool.entries.items) |i, e| {
        strings[i] = string_buffer[e.begin..e.end];
    }

    const num_field_names = self.field_name_pool.entries.items.len;
    const field_name_buffer = try allocator.dupe(u8, self.field_name_pool.getContiguous());
    var field_names = try allocator.alloc([]const u8, num_field_names);

    for (0.., self.field_name_pool.entries.items) |i, e| {
        field_names[i] = field_name_buffer[e.begin..e.end];
    }

    return .{
        .code = code,
        .entry = entry,
        .strings = strings,
        .field_names = field_names,
        .deinit_data = .{
            .allocator = allocator,
            .strings = string_buffer,
            .field_names = field_name_buffer,
        },
    };
}

fn asmString(self: *Asm) !void {
    _ = try self.expectKw(.string, "expected '-string'");
    const name = (try self.expect(.identifier, "expected string identifier")).where;

    self.str_build.clearRetainingCapacity();
    var writer = self.str_build.writer();

    const content = (try self.expect(.string, "expected string literal")).where;
    var escaped = try self.str_parser.parse(content);
    _ = try writer.write(escaped);

    while (try self.scan.peek()) |peeked| {
        if (peeked.tag != .string) {
            break;
        }
        escaped = try self.str_parser.parse(peeked.where);
        _ = try writer.write(escaped);
        _ = try self.scan.next();
    }

    const pool_id = try self.string_pool.getOrIntern(self.str_build.items);
    try self.str_patcher.decl(name, pool_id);
}

fn asmFunc(self: *Asm) !void {
    _ = try self.expectKw(.function, "expected '-function'");
    const name = try self.expect(.identifier, "expected function identifier");
    _ = try self.expectKw(.begin, "expected '-begin'");
    try self.fn_patcher.decl(name.where, self.code.items.len);
    if (std.mem.eql(u8, name.where, "main")) {
        self.entry = self.code.items.len;
    }
    self.lbl_patcher.reset();

    const found_end = parse: while (try self.scan.peek()) |tok| {
        switch (tok.tag) {
            .label => self.asmLabel() catch |err| {
                if (err == std.mem.Allocator.Error.OutOfMemory) {
                    return err;
                } else {
                    try self.syncUntilNextStmt();
                }
            },
            .instr => self.asmInstr() catch |err| {
                if (err == std.mem.Allocator.Error.OutOfMemory) {
                    return err;
                } else {
                    try self.syncUntilNextStmt();
                }
            },
            else => {
                _ = try self.expectKw(.end, "expected next instruction or '-end'");
                break :parse true;
            },
        }
    } else false;

    if (!found_end) _ = try self.expectKw(.end, "expected next instruction or '-end'");

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
                const func = try self.expect(.identifier, "expected function identifier");
                try self.fn_patcher.reference(func.where, offset);
            },
            .jmp, .jmpnz => {
                const lbl = try self.expect(.label, "expected label");
                try self.lbl_patcher.reference(lbl.where, offset);
            },
            .pushf => {
                const float_ = try self.expect(.float, "expected float");
                self.code.items[offset].operand = .{
                    .float = float_.tag.float,
                };
            },
            .pushs => {
                const identifier = try self.expect(.identifier, "expected string identifier");
                try self.str_patcher.reference(identifier.where, offset);
            },
            .struct_load, .struct_store => {
                const name = try self.expect(.identifier, "expected field identifier");
                const id = try self.field_name_pool.getOrIntern(name.where);
                self.code.items[offset].operand = .{ .field_id = id };
            },
            else => {
                const int = try self.expect(.int, "expected integer");
                self.code.items[offset].operand = .{
                    .int = int.tag.int,
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
            .tag = .@"Unexpected end of input",
            .where = self.scan.source[self.scan.source.len - 1 ..],
            .extra = extra,
        });
        return error.UnexpectedEOF;
    };
}

fn expect(self: *Asm, tag: std.meta.Tag(Token.Tag), extra: ?[]const u8) !Token {
    const tok = try self.getToken(extra);
    if (tok.tag == .err) {
        return error.InvalidToken;
    }
    if (tok.tag != tag) {
        try self.errors.append(.{
            .tag = .@"Unexpected token",
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
            .tag = .@"Unexpected token",
            .where = tok.where,
            .extra = extra,
        });
        return error.UnexpectedToken;
    }
    return tok;
}

fn syncUntilNextToplevel(self: *Asm) !void {
    while (try self.scan.peek()) |tok| {
        if (tok.tag == .keyword and (tok.tag.keyword == .function or tok.tag.keyword == .string)) break;
        _ = try self.scan.next();
    }
}

fn syncUntilNextStmt(self: *Asm) !void {
    while (try self.scan.peek()) |tok| {
        if (tok.tag == .instr or (tok.tag == .keyword and tok.tag.keyword == .end)) break;
        _ = try self.scan.next();
    }
}
