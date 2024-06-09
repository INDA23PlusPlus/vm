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
    global: usize,
    function: usize,
    string: usize,
    field_name: []const u8,
};

ast: *Ast,
symtab: *SymbolTable,
source: []const u8,
instr_toks: ArrayList([]const u8),
instr_tok_stack: ArrayList(ArrayList([]const u8)),
code: ArrayList(u8),
functions: ArrayList(ArrayList(u8)),
param_counts: ArrayList(usize),
label_counter: usize,
string_ids: ArrayList(usize),
allocator: Allocator,
prong_labels: ArrayList(ArrayList(usize)),

pub fn init(
    ast: *Ast,
    symtab: *SymbolTable,
    source: []const u8,
    allocator: Allocator,
) CodeGen {
    return .{
        .ast = ast,
        .symtab = symtab,
        .source = source,
        .instr_toks = ArrayList([]const u8).init(allocator),
        .instr_tok_stack = ArrayList(ArrayList([]const u8)).init(allocator),
        .code = ArrayList(u8).init(allocator),
        .functions = ArrayList(ArrayList(u8)).init(allocator),
        .allocator = allocator,
        .label_counter = 0,
        .param_counts = ArrayList(usize).init(allocator),
        .string_ids = ArrayList(usize).init(allocator),
        .prong_labels = ArrayList(ArrayList(usize)).init(allocator),
    };
}

pub fn deinit(self: *CodeGen) void {
    self.instr_toks.deinit();
    self.code.deinit();
    self.functions.deinit();
    self.param_counts.deinit();
    self.string_ids.deinit();
    self.prong_labels.deinit();
    self.instr_tok_stack.deinit();
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

fn currentProngLabels(self: *CodeGen) *ArrayList(usize) {
    return &self.prong_labels.items[self.prong_labels.items.len - 1];
}

fn newProngLabel(self: *CodeGen) !usize {
    const label = self.newLabel();
    try self.currentProngLabels().append(label);
    return label;
}

fn pushProngLabels(self: *CodeGen) !void {
    try self.prong_labels.append(ArrayList(usize).init(self.allocator));
}

fn popProngLabels(self: *CodeGen) void {
    self.currentProngLabels().deinit();
    _ = self.prong_labels.pop();
}

fn beginFunction(self: *CodeGen, symid: usize) !void {
    try self.functions.append(ArrayList(u8).init(self.allocator));
    try self.instr_tok_stack.append(ArrayList([]const u8).init(self.allocator));
    const writer = self.currentFunction().writer();
    const symbol = self.symtab.getSymbol(symid);
    try writer.writeAll("-function ");
    try self.writeFuncName(symid, writer);
    try writer.print(
        \\
        \\-begin
        \\
    ,
        .{},
    );
    if (symbol.kind.func > 0) {
        try self.writeInstr(
            .stack_alloc,
            .{ .int = @intCast(symbol.kind.func) },
            self.placeholderToken(),
        );
    }
    try self.param_counts.append(symbol.nparams);
}

fn endFunction(self: *CodeGen) !void {
    const writer = self.currentFunction().writer();
    try self.writeInstr(.ret, .none, self.source[self.source.len - 1 .. self.source.len]);
    try writer.writeAll(
        \\-end
        \\
        \\
    );
    try self.code.writer().writeAll(self.currentFunction().items);
    try self.instr_toks.appendSlice(self.currentInstrToks().items);
    self.currentFunction().deinit();
    self.currentInstrToks().deinit();
    _ = self.functions.pop();
    _ = self.instr_tok_stack.pop();
    _ = self.param_counts.pop();
}

fn currentFunction(self: *CodeGen) *ArrayList(u8) {
    return &self.functions.items[self.functions.items.len - 1];
}

fn currentInstrToks(self: *CodeGen) *ArrayList([]const u8) {
    return &self.instr_tok_stack.items[self.instr_tok_stack.items.len - 1];
}

fn currentParamCount(self: *CodeGen) usize {
    return self.param_counts.getLast();
}

fn writeInstr(
    self: *CodeGen,
    opcode: Opcode,
    operand: Operand,
    token: []const u8,
) !void {
    const writer = self.currentFunction().writer();
    try writer.print("    {s: <16}", .{@tagName(opcode)});
    switch (operand) {
        .float_str => |v| try writer.print("@{s}", .{v}),
        .int_str => |v| try writer.print("%{s}", .{v}),
        .int => |v| try writer.print("%{d}", .{v}),
        .label => |v| try writer.print(".L{d}", .{v}),
        .global => |v| try writer.print("$~glob{d}", .{v}),
        .function => |v| try self.writeFuncName(v, writer),
        .string => |v| try writer.print("$~str{d}", .{v}),
        .field_name => |v| try writer.print("${s}", .{v}),
        .none => {},
    }
    try writer.print("\n", .{});
    try self.currentInstrToks().append(token);
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
    try self.functions.append(ArrayList(u8).init(self.allocator));
    try self.instr_tok_stack.append(ArrayList([]const u8).init(self.allocator));
    try self.currentFunction().writer().print(
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
            // lists need to be deep copied and duplicated if they are mutated
            switch (v.op.tag) {
                .@"::", .@"++" => {
                    try self.writeInstr(.deep_copy, .none, v.op.where);
                    try self.writeInstr(.dup, .none, v.op.where);
                },
                else => {},
            }
            try self.genNode(v.rhs);
            const opcode: Opcode = switch (v.op.tag) {
                .@"=" => .cmp_eq,
                .@"<" => .cmp_lt,
                .@"<=" => .cmp_le,
                .@">" => .cmp_gt,
                .@">=" => .cmp_ge,
                .@"!=" => .cmp_ne,
                .@"+", .@"or" => .add,
                .@"++" => .list_concat,
                .@"::" => .list_append,
                .@"-" => .sub,
                .@"*", .@"and" => .mul,
                .@"/" => .div,
                .@"%" => .mod,
                else => unreachable,
            };
            try self.writeInstr(opcode, .none, v.op.where);
        },
        .unop => |v| {
            switch (v.op.tag) {
                .neg => {
                    try self.writeInstr(.push, .{ .int = 0 }, v.op.where);
                    try self.genNode(v.opnd);
                    try self.writeInstr(.sub, .none, v.op.where);
                },
                else => unreachable,
            }
        },
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
                    if (symbol.is_const) {
                        try self.genNode(v.expr);
                        try self.writeInstr(.glob_store, .{ .global = v.symid }, v.name);
                    } else {
                        try self.genNode(v.expr);
                        try self.writeInstr(.store, .{ .int = @intCast(w) }, v.assign_where);
                    }
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
                    if (v.args) |args| try self.genNode(args);
                    try self.writeInstr(.push, .{ .int = @intCast(symbol.nparams) }, v.name);
                    try self.writeInstr(.call, .{ .function = v.symid }, v.name);
                },
                .local => |offset| {
                    if (symbol.is_const) {
                        try self.writeInstr(.glob_load, .{ .global = v.symid }, v.name);
                        try self.writeInstr(.deep_copy, .none, v.name);
                    } else {
                        try self.writeInstr(.load, .{ .int = @intCast(offset) }, v.name);
                    }
                },
                .param => |index| {
                    const offset = @as(i64, @intCast(index)) - 3 - @as(i64, @intCast(self.currentParamCount()));
                    try self.writeInstr(.load, .{ .int = offset }, v.name);
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
            try self.writeInstr(.syscall, .{ .int = 1 }, self.placeholderToken());
            try self.writeInstr(.stack_alloc, .{ .int = 1 }, self.placeholderToken());
        },
        .println => |v| {
            try self.genNode(v);
            try self.writeInstr(.syscall, .{ .int = 0 }, self.placeholderToken());
            try self.writeInstr(.stack_alloc, .{ .int = 1 }, self.placeholderToken());
        },
        .compound => |v| {
            try self.genNode(v.discard);
            try self.writeInstr(.pop, .none, self.placeholderToken());
            try self.genNode(v.keep);
        },
        .list => |v| {
            try self.writeInstr(.list_alloc, .none, v.leading_brk);
            if (v.items) |items| try self.genNode(items);
        },
        .item => |v| {
            try self.writeInstr(.dup, .none, self.placeholderToken());
            try self.genNode(v.expr);
            try self.writeInstr(.list_append, .none, self.placeholderToken());
            if (v.next) |next| try self.genNode(next);
        },
        .indexing => |v| {
            try self.genNode(v.list);
            try self.genNode(v.index);
            try self.writeInstr(.list_load, .none, v.where);
        },
        .len => |v| {
            try self.genNode(v.list);
            try self.writeInstr(.list_length, .none, v.where);
        },
        .struct_ => |v| {
            try self.writeInstr(.struct_alloc, .none, v.leading_brc);
            if (v.fields) |fields| try self.genNode(fields);
        },
        .field_decl => |v| {
            try self.writeInstr(.dup, .none, self.placeholderToken());
            try self.genNode(v.expr);
            try self.writeInstr(.struct_store, .{ .field_name = v.name }, v.name);
            if (v.next) |next| try self.genNode(next);
        },
        .field_access => |v| {
            try self.genNode(v.struct_);
            try self.writeInstr(.struct_load, .{ .field_name = v.field }, v.dot);
        },
        .infix => |v| {
            try self.genNode(v.lhs);
            try self.genNode(v.rhs);
            try self.writeInstr(.push, .{ .int = 2 }, self.placeholderToken());
            try self.writeInstr(.call, .{ .function = v.symid }, v.name);
        },
        .match => |v| {
            try self.genNode(v.expr);
            const done_label = self.newLabel();

            try self.pushProngLabels();

            var opt_prong_id = v.prongs;
            while (opt_prong_id) |prong_id| {
                const prong = self.ast.getNode(prong_id).prong;
                try self.writeInstr(.dup, .none, self.placeholderToken());
                try self.genNode(prong.lhs);
                try self.writeInstr(.cmp_eq, .none, prong.where);
                const label = try self.newProngLabel();
                try self.writeInstr(.jmpnz, .{ .label = label }, self.placeholderToken());
                opt_prong_id = prong.next;
            }

            try self.genNode(v.default);
            try self.writeInstr(.jmp, .{ .label = done_label }, self.placeholderToken());

            opt_prong_id = v.prongs;
            var label_id: usize = 0;
            while (opt_prong_id) |prong_id| {
                const prong = self.ast.getNode(prong_id).prong;
                const label = self.currentProngLabels().items[label_id];
                try self.writeLabel(label);
                try self.genNode(prong.rhs);

                opt_prong_id = prong.next;
                label_id += 1;

                if (opt_prong_id) |_| {
                    try self.writeInstr(.jmp, .{ .label = done_label }, self.placeholderToken());
                }
            }

            try self.writeLabel(done_label);
            self.popProngLabels();
        },
        .prong => undefined, // handled in 'match'
    }
}
