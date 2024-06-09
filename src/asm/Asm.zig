//!
//! The intermediate language assembler.
//!

const Asm = @This();
const std = @import("std");
const arch = @import("arch");
const Instruction = arch.Instruction;
const Program = arch.Program;
const Patcher = @import("Patcher.zig");
const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;
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
diagnostics: *DiagnosticList,
str_build: std.ArrayList(u8),
str_parser: StringParser,
instr_toks: std.ArrayList([]const u8),
curr_fn_addr: usize,
fn_tbl: std.ArrayList(Program.Symbol),

pub fn init(
    source: []const u8,
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
) Asm {
    return .{
        .code = std.ArrayList(Instruction).init(allocator),
        .scan = .{ .source = source, .diagnostics = diagnostics },
        .fn_patcher = Patcher.init(allocator, diagnostics),
        .lbl_patcher = Patcher.init(allocator, diagnostics),
        .str_patcher = Patcher.init(allocator, diagnostics),
        .string_pool = StringPool.init(allocator),
        .field_name_pool = StringPool.init(allocator),
        .diagnostics = diagnostics,
        .entry = null,
        .str_build = std.ArrayList(u8).init(allocator),
        .str_parser = StringParser.init(allocator, diagnostics),
        .instr_toks = std.ArrayList([]const u8).init(allocator),
        .curr_fn_addr = 0,
        .fn_tbl = std.ArrayList(Program.Symbol).init(allocator),
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
    self.instr_toks.deinit();
    self.fn_tbl.deinit();
}

pub fn assemble(self: *Asm) !void {
    while (try self.scan.peek()) |leading| {
        if (leading.tag != .keyword) {
            try self.diagnostics.addDiagnostic(.{
                .description = .{ .static = "unexpected token, expected '-function' or '-string'" },
                .location = leading.where,
            });
            try self.syncUntilNextToplevel();
            continue;
        }

        const result = switch (leading.tag.keyword) {
            .function => self.asmFunc(),
            .string => self.asmString(),
            else => {
                try self.diagnostics.addDiagnostic(.{
                    .description = .{ .static = "unexpected token, expected '-string' or '-function'" },
                    .location = leading.where,
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
        try self.diagnostics.addDiagnostic(.{
            .description = .{ .static = "missing 'main' function" },
        });
    }
}

/// Options for embedding source code in final program.
pub const EmbeddedSourceOptions = union(enum) {
    /// Don't include source in final program.
    none,
    /// Embedd assembly source and instruction tokens.
    vemod,
    /// Provide source and tokens from frontend source.
    /// Tokens and instructions are associated by having the same
    /// index in `tokens` and `code` respectively.
    frontend: struct {
        tokens: []const []const u8,
        source: []const u8,
    },
};

fn remapTokens(
    org_src: []const u8,
    new_src: []const u8,
    tokens: []const []const u8,
    allocator: std.mem.Allocator,
) ![]const []const u8 {
    const new_toks = try allocator.dupe([]const u8, tokens);
    const org_addr: usize = @intFromPtr(org_src.ptr);
    const new_addr: usize = @intFromPtr(new_src.ptr);

    if (org_addr > new_addr) {
        const diff = org_addr - new_addr;
        for (new_toks) |*tok| {
            const tok_addr: usize = @intFromPtr(tok.ptr);
            tok.ptr = @ptrFromInt(tok_addr - diff);
        }
    } else {
        const diff = new_addr - org_addr;
        for (new_toks) |*tok| {
            const tok_addr: usize = @intFromPtr(tok.ptr);
            tok.ptr = @ptrFromInt(tok_addr + diff);
        }
    }

    return new_toks;
}

/// Copies relevant data and constructs a VM program.
pub fn getProgram(
    self: *Asm,
    allocator: std.mem.Allocator,
    src_opts: EmbeddedSourceOptions,
) !Program {
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

    var tokens: ?[]const []const u8 = null;
    var source: ?[]const u8 = null;

    switch (src_opts) {
        .none => {},
        .vemod => {
            source = try allocator.dupe(u8, self.scan.source);
            tokens = try remapTokens(
                self.scan.source,
                source.?,
                self.instr_toks.items,
                allocator,
            );
        },
        .frontend => |fe| {
            source = try allocator.dupe(u8, fe.source);
            tokens = try remapTokens(fe.source, source.?, fe.tokens, allocator);
        },
    }

    return .{
        .code = code,
        .entry = entry,
        .strings = strings,
        .field_names = field_names,
        .tokens = tokens,
        // TODO: make this optional
        .fn_tbl = try self.fn_tbl.clone(),
        .deinit_data = .{
            .allocator = allocator,
            .strings = string_buffer,
            .field_names = field_name_buffer,
            .source = source,
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
    self.curr_fn_addr = self.code.items.len;
    _ = try self.expectKw(.function, "expected '-function'");
    const name = try self.expect(.identifier, "expected function identifier");
    _ = try self.expectKw(.begin, "expected '-begin'");
    try self.fn_patcher.decl(name.where, self.code.items.len);
    if (std.mem.eql(u8, name.where, entry_name)) {
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

    // add implicit return unit at end of function
    // if the last statement is not `ret`.
    // if the current function is main, return 0.
    if (self.code.items.len == self.curr_fn_addr or self.code.getLast().op != .ret) {
        const value = if (std.mem.eql(u8, name.where, entry_name)) Instruction{
            .op = .push,
            .operand = .{ .int = 0 },
        } else Instruction{
            .op = .stack_alloc,
            .operand = .{ .int = 1 },
        };
        const implicit_return = Instruction{ .op = .ret };
        try self.code.append(value);
        try self.code.append(implicit_return);
        // we need to add dummy tokens to align code with token list
        try self.instr_toks.appendNTimes(self.scan.source[0..0], 2);
    }

    try self.fn_tbl.append(.{ .name = null, .addr = self.curr_fn_addr, .size = self.code.items.len - self.curr_fn_addr });
}

fn asmInstr(self: *Asm) !void {
    const instr = try self.expect(.instr, null);
    try self.instr_toks.append(instr.where);
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
        const description: diagnostic.Description = if (extra) |extra_| .{
            .dynamic = try self.diagnostics.newDynamicDescription(
                "unexpected end of input, {s}",
                .{extra_},
            ),
        } else .{ .static = "unexpected end of input" };
        try self.diagnostics.addDiagnostic(.{
            .description = description,
            .location = self.scan.source[self.scan.source.len - 1 ..],
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
        const description: diagnostic.Description = if (extra) |extra_| .{
            .dynamic = try self.diagnostics.newDynamicDescription(
                "unexpected token, {s}",
                .{extra_},
            ),
        } else .{ .static = "unexpected token" };
        try self.diagnostics.addDiagnostic(.{
            .description = description,
            .location = tok.where,
        });
        return error.UnexpectedToken;
    }
    return tok;
}

fn expectKw(self: *Asm, kw: Token.Keyword, extra: ?[]const u8) !Token {
    const tok = try self.expect(.keyword, extra);
    if (tok.tag.keyword != kw) {
        const description: diagnostic.Description = if (extra) |extra_| .{
            .dynamic = try self.diagnostics.newDynamicDescription(
                "unexpected token, {s}",
                .{extra_},
            ),
        } else .{ .static = "unexpected token" };
        try self.diagnostics.addDiagnostic(.{
            .description = description,
            .location = self.scan.source[self.scan.source.len - 1 ..],
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
