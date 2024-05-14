//!
//! Verifies that constants are initialized correctly
//!

const ConstantVerify = @This();

const Ast = @import("Ast.zig");
const SymbolTable = @import("SymbolTable.zig");
const DiagnosticList = @import("diagnostic").DiagnosticList;

ast: *const Ast,
symtab: *const SymbolTable,
diagnostics: *DiagnosticList,
inside_const: bool,
const_where: []const u8,

pub fn init(
    ast: *const Ast,
    symtab: *const SymbolTable,
    diagnostics: *DiagnosticList,
) ConstantVerify {
    return .{
        .ast = ast,
        .symtab = symtab,
        .diagnostics = diagnostics,
        .inside_const = false,
        .const_where = undefined,
    };
}

pub fn deinit(self: *ConstantVerify) void {
    // nothing to do here
    _ = self;
}

pub fn verify(self: *ConstantVerify) !void {
    try self.verifyNode(self.ast.root);
}

fn verifyNode(self: *ConstantVerify, node_id: usize) !void {
    const node: *const Ast.Node = self.ast.getNode(node_id);

    switch (node) {
        .binop => |v| {
            try self.verifyNode(v.lhs);
            try self.verifyNode(v.rhs);
        },
        .unop => |v| try self.verifyNode(v.opnd),
        .if_expr => |v| {
            try self.verifyNode(v.cond);
            try self.verifyNode(v.then);
            try self.verifyNode(v.else_);
        },
        .let_expr => |v| {},
        .let_entry => |v| {},
        .param => |v| {},
        .reference => |v| {},
        .arg => |v| {},
        .string => |v| {},
        .number => |v| {},
        .unit => |v| {},
        .print => |v| {},
        .compound => |v| {},
        .list => |v| {},
        .item => |v| {},
        .indexing => |v| {},
        .len => |v| {},
        .struct_ => |v| {},
        .field_access => |v| {},
        .field_decl => |v| {},
        .infix => |v| {},
        .match => |v| {},
        .prong => |v| {},
    }
}
