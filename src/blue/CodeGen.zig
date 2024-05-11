//!
//! VeMod assembly generation from Blue.
//!
const CodeGen = @This();
const SymbolTable = @import("SymbolTable.zig");
const Ast = @import("Ast.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Error = @import("asm").Error;
const Opcode = @import("arch").Opcode;
const Token = @import("Token.zig");

const Operand = union(enum) {
    none,
    int: i64,
    float_str: []const u8,
    int_str: []const u8,
    label: usize,
    function: usize,
    string: usize,
};

ast: *Ast,
symtab: *SymbolTable,
source: []const u8,
instr_toks: ArrayList([]const u8),
code: ArrayList(u8),
functions: ArrayList(ArrayList(u8)),
param_counts: ArrayList(usize),
local_counts: ArrayList(usize),
errors: *ArrayList(Error),
label_counter: usize,
string_ids: ArrayList(usize),
allocator: Allocator,

pub fn init(
    ast: *Ast,
    symtab: *SymbolTable,
    source: []const u8,
    errors: *ArrayList(Error),
    allocator: Allocator,
) CodeGen {
    return .{
        .ast = ast,
        .symtab = symtab,
        .source = source,
        .instr_toks = ArrayList([]const u8).init(allocator),
        .code = ArrayList(u8).init(allocator),
        .functions = ArrayList(ArrayList(u8)).init(allocator),
        .errors = errors,
        .allocator = allocator,
        .label_counter = 0,
        .param_counts = ArrayList(usize).init(allocator),
        .local_counts = ArrayList(usize).init(allocator),
        .string_ids = ArrayList(usize).init(allocator),
    };
}

pub fn deinit(self: *CodeGen) void {
    self.instr_toks.deinit();
    self.code.deinit();
    self.functions.deinit();
    self.param_counts.deinit();
    self.local_counts.deinit();
    self.string_ids.deinit();
}

fn placeholderToken(self: *const CodeGen) []const u8 {
    return self.source[0..0];
}

fn writeFuncName(self: *CodeGen, symid: usize, writer: anytype) !void {
    const symbol = &self.symtab.symbols.items[symid];
    try writer.print("${s}_{d}", .{ symbol.decl_loc, symid });
}

fn pushString(self: *CodeGen, node_id: usize) !usize {
    const index = self.string_ids.items.len;
    try self.string_ids.append(node_id);
    return index;
}

fn beginFunction(self: *CodeGen, symid: usize) !void {
    try self.functions.append(ArrayList(u8).init(self.allocator));
    const writer = self.currentFunction().writer();
    try writer.writeAll("-function ");
    try self.writeFuncName(symid, writer);
    try writer.print(
        \\
        \\-begin
        \\
    ,
        .{},
    );
    try self.writeInstr(
        .stack_alloc,
        .{ .int = @intCast(self.symtab.getSymbol(symid).kind.func) },
        self.placeholderToken(),
    );
    try self.param_counts.append(self.symtab.getSymbol(symid).nparams);
    try self.local_counts.append(self.symtab.getSymbol(symid).kind.func);
}

fn endFunction(self: *CodeGen) !void {
    const writer = self.currentFunction().writer();
    try self.writeInstr(.ret, .none, self.placeholderToken());
    try writer.writeAll(
        \\-end
        \\
        \\
    );
    try self.code.writer().writeAll(self.currentFunction().items);
    self.currentFunction().deinit();
    _ = self.functions.pop();
    _ = self.param_counts.pop();
    _ = self.local_counts.pop();
}

fn currentFunction(self: *CodeGen) *ArrayList(u8) {
    return &self.functions.items[self.functions.items.len - 1];
}

fn writeInstr(
    self: *CodeGen,
    opcode: Opcode,
    operand: Operand,
    token: []const u8,
) !void {
    const writer = self.currentFunction().writer();
    try writer.writeAll("    ");
    try writer.writeAll(@tagName(opcode));
    try writer.writeByte(' ');
    switch (operand) {
        .float_str => |v| try writer.print("@{s}", .{v}),
        .int_str => |v| try writer.print("%{s}", .{v}),
        .int => |v| try writer.print("%{d}", .{v}),
        .label => |v| try writer.print(".L{d}", .{v}),
        .function => |v| try self.writeFuncName(v, writer),
        .string => |v| try writer.print("$~str{d}", .{v}),
        .none => {},
    }
    // try writer.print(" # {s}\n", .{token});
    try writer.print("\n", .{});
    try self.instr_toks.append(token);
}

fn appendStringConstants(self: *CodeGen) !void {
    for (self.string_ids.items, 0..) |nid, i| {
        const node = self.ast.nodes.items[nid];
        const str = node.string.where;
        try self.code.writer().print(
            \\-string $~str{d} "{s}"
            \\
        ,
            .{ i, str },
        );
    }
}

fn newLabel(self: *CodeGen) usize {
    defer self.label_counter += 1;
    return self.label_counter;
}

fn writeLabel(self: *CodeGen, id: usize) !void {
    const writer = self.currentFunction().writer();
    try writer.print(".L{d}\n", .{id});
}

pub fn gen(self: *CodeGen) !void {
    const ptr = try self.functions.addOne();
    ptr.* = ArrayList(u8).init(self.allocator);
    try ptr.writer().print(
        \\-function $main
        \\-begin
        \\
    ,
        .{},
    );
    try self.writeInstr(
        .stack_alloc,
        .{ .int = @intCast(self.symtab.mainLocalCount()) },
        self.placeholderToken(),
    );
    try self.local_counts.append(self.symtab.mainLocalCount());
    try self.param_counts.append(0);
    try self.genNode(self.ast.root);
    try self.endFunction();
    try self.appendStringConstants();
}

pub fn genNode(self: *CodeGen, node_id: usize) !void {
    const node = &self.ast.nodes.items[node_id];
    switch (node.*) {
        .binop => |v| {
            try self.genNode(v.lhs);
            try self.genNode(v.rhs);
            const opcode: Opcode = switch (v.op.tag) {
                .@"=" => .cmp_eq,
                .@"<" => .cmp_lt,
                .@"<=" => .cmp_le,
                .@">" => .cmp_gt,
                .@">=" => .cmp_ge,
                .@"!=" => .cmp_ne,
                .@"+" => .add,
                .@"++" => .list_concat,
                .@"::" => .list_append,
                .@"-" => .sub,
                .@"*" => .mul,
                .@"/" => .div,
                .@"%" => .mod,
                .@"and", .@"or" => std.debug.panic("no logical operators supported", .{}),
                else => unreachable,
            };
            try self.writeInstr(opcode, .none, v.op.where);
        },
        .unop => std.debug.panic("no unary operators supported", .{}),
        .if_expr => |v| {
            const then_label = self.newLabel();
            const done_label = self.newLabel();
            try self.genNode(v.cond);
            try self.writeInstr(.jmpnz, .{ .label = then_label }, self.placeholderToken());
            try self.genNode(v.else_);
            try self.writeInstr(.jmp, .{ .label = done_label }, self.placeholderToken());
            try self.writeLabel(then_label);
            try self.genNode(v.then);
            try self.writeLabel(done_label);
        },
        .let_expr => |v| {
            try self.genNode(v.stmts);
            try self.genNode(v.in);
        },
        .let_entry => |v| {
            const symbol = self.symtab.getSymbol(v.symid);
            switch (symbol.kind) {
                .func => {
                    try self.beginFunction(v.symid);
                    try self.genNode(v.expr);
                    try self.endFunction();
                },
                .local => |w| {
                    try self.genNode(v.expr);
                    try self.writeInstr(.store, .{ .int = @intCast(w) }, v.assign_where);
                },
                .param => unreachable,
            }
            if (v.next) |next| {
                try self.genNode(next);
            }
        },
        .param => {},
        .reference => |v| {
            const symbol = self.symtab.getSymbol(v.symid);
            switch (symbol.kind) {
                .func => {
                    try self.genNode(v.args.?);
                    try self.writeInstr(.push, .{ .int = @intCast(symbol.nparams) }, symbol.decl_loc);
                    try self.writeInstr(.call, .{ .function = v.symid }, symbol.decl_loc);
                },
                .local => |offset| {
                    try self.writeInstr(.load, .{ .int = @intCast(offset) }, symbol.decl_loc);
                },
                .param => |index| {
                    const offset = @as(i64, @intCast(index)) - 4;
                    try self.writeInstr(.load, .{ .int = offset }, symbol.decl_loc);
                },
            }
        },
        .arg => |v| {
            try self.genNode(v.expr);
            if (v.next) |next| try self.genNode(next);
        },
        .string => |v| {
            const index = try self.pushString(node_id);
            try self.writeInstr(.pushs, .{ .string = index }, v.where);
        },
        .number => |v| {
            switch (v.tag) {
                .int => try self.writeInstr(.push, .{ .int_str = v.where }, v.where),
                .float => try self.writeInstr(.pushf, .{ .float_str = v.where }, v.where),
                else => unreachable,
            }
        },
        .unit => |v| try self.writeInstr(.stack_alloc, .{ .int = 1 }, v.where),
        .print => |v| {
            try self.genNode(v);
            try self.writeInstr(.syscall, .{ .int = 0 }, self.placeholderToken());
            try self.writeInstr(.stack_alloc, .{ .int = 1 }, self.placeholderToken());
        },
        .compound => |v| {
            try self.genNode(v.discard);
            try self.writeInstr(.pop, .none, self.placeholderToken());
            try self.genNode(v.keep);
        },
    }
}
