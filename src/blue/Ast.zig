//!
//! Abstract syntax tree representation
//!
const Ast = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Token = @import("Token.zig");

pub const Node = union(enum) {
    binop: struct { lhs: usize, rhs: usize, op: Token },
    unop: struct { opnd: usize, op: Token },
    if_expr: struct { cond: usize, then: usize, else_: usize },
    let_expr: struct { stmts: usize, in: usize },
    let_entry: struct {
        name: []const u8,
        symid: usize = 0,
        params: ?usize,
        expr: usize,
        next: ?usize = null,
        assign_where: []const u8,
        is_const: bool,
    },
    param: struct { name: []const u8, symid: usize = 0, next: ?usize },
    reference: struct { name: []const u8, symid: usize = 0, args: ?usize },
    arg: struct { expr: usize, next: ?usize },
    string: Token,
    number: Token,
    unit: Token,
    print: usize,
    println: usize,
    compound: struct { discard: usize, keep: usize },
    list: struct { items: ?usize },
    item: struct { expr: usize, next: ?usize },
    indexing: struct { list: usize, index: usize, where: []const u8 },
    len: struct { list: usize, where: []const u8 },
    struct_: struct { fields: ?usize },
    field_access: struct { struct_: usize, field: []const u8, dot: []const u8 },
    field_decl: struct { name: []const u8, expr: usize, next: ?usize },
    infix: struct { lhs: usize, rhs: usize, name: []const u8, symid: usize = 0 },
    match: struct { expr: usize, prongs: ?usize, default: usize },
    prong: struct { lhs: usize, rhs: usize, next: ?usize, where: []const u8 },
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
    try ast.nodes.append(nd);
    return id;
}

pub fn print(ast: *Ast, writer: anytype) !void {
    try printNode(ast, ast.root, writer);
}

pub fn getNode(ast: *Ast, id: usize) *Node {
    return &ast.nodes.items[id];
}

fn printNode(ast: *Ast, id: usize, writer: anytype) !void {
    const info = @typeInfo(Node);
    const mem = std.mem;
    const node = ast.nodes.items[id];

    try writer.print("({s}: ", .{@tagName(node)});

    inline for (info.Union.fields) |field| {
        if (mem.eql(u8, field.name, @tagName(node))) {
            const variant = @field(node, field.name);
            const VarType = @TypeOf(variant);

            switch (VarType) {
                Token => try writer.writeAll(variant.where),
                usize => try ast.printNode(variant, writer),
                else => {
                    const var_info = @typeInfo(VarType);
                    inline for (var_info.Struct.fields, 0..) |varf, i| {
                        comptime if (mem.eql(u8, varf.name, "symid")) continue;
                        try writer.print("{s}: ", .{varf.name});

                        switch (varf.type) {
                            Token => try writer.writeAll(@field(variant, varf.name).where),
                            ?usize => {
                                if (@field(variant, varf.name)) |cid| {
                                    try ast.printNode(cid, writer);
                                } else try writer.writeAll("<null>");
                            },
                            usize => try ast.printNode(@field(variant, varf.name), writer),
                            []const u8 => try writer.writeAll(@field(variant, varf.name)),
                            else => unreachable,
                        }

                        if (i < var_info.Struct.fields.len - 1)
                            try writer.writeAll(", ");
                    }
                },
            }
        }
    }

    try writer.writeByte(')');
}
