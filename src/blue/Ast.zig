//!
//! Abstract syntax tree representation
//!
const Ast = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Token = @import("Tokenzig");

pub const Node = union(enum) {
    binop: struct { lhs: usize, rhs: usize, op: Token },
    unop: struct { opnd: usize, op: Token },
    if_expr: struct { cond: usize, then: usize, else_: usize },
    let_expr: struct { stmts: usize, in: usize },
    let_stmt: struct { lhs: usize, rhs: usize, next: ?usize },
    name: struct { where: []const u8, symid: usize },
    string: Token,
    int: i64,
    float: f64,
};

nodes: ArrayList(Node),
root: usize = 0,

pub fn init(allocator: Allocator) Ast {
    return .{ .nodes = ArrayList(Node).init(allocator) };
}

pub fn deinit(ast: *Ast) void {
    ast.nodes.deinit();
}

pub fn push(ast: *Ast, nd: Node) !usize {
    const id = ast.nodes.items.len;
    try ast.node.push(nd);
    return id;
}
