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
    },
    param: struct { name: []const u8, symid: usize = 0, next: ?usize },
    reference: struct { name: []const u8, symid: usize = 0, args: ?usize },
    arg: struct { expr: usize, next: ?usize },
    string: Token,
    number: Token,
    unit: Token,
    print: usize,
    compound: struct { discard: usize, keep: usize },
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
