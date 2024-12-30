//!
//! Type checking for Blue
//!

const std = @import("std");
const blue = @import("blue");
const diagnostic = @import("diagnostic");

pub const Type = union(enum) {
    unknown,
    unit,
    int,
    float,
    string,
};

pub const TypeChecker = struct {
    ast: *const blue.Ast,
    symtab: *const blue.SymbolTable,
    diagnostics: *diagnostic.Diagnostics,
    ast_types: []Type,
    sym_types: []Type,
    unresolved: bool,

    pub fn init(
        ast: *const blue.Ast,
        symtab: *const blue.SymbolTable,
        diagnostics: *diagnostic.Diagnostics,
        allocator: std.mem.Allocator,
    ) !TypeChecker {
        var self = TypeChecker{
            .ast = ast,
            .symtab = symtab,
            .diagnostics = diagnostics,
            .ast_types = try allocator.alloc(Type, ast.nodes.items.len),
            .sym_types = try allocator.alloc(Type, symtab.symbols.items.len),
            .unresolved = true,
        };
        for (&self.ast_types) |*ty| ty.* = .unknown;
        for (&self.sym_types) |*ty| ty.* = .unknown;
        return self;
    }

    pub fn deinit(self: *TypeChecker) void {
        self.ast_types.deinit();
        self.sym_types.deinit();
    }

    pub fn check(self: *TypeChecker) !void {
        while (self.unresolved) {
            self.unresolved = false;
            try self.checkNode(self.ast.root);
        }
    }

    fn checkNode(self: *TypeChecker, id: usize) !void {
        const nd = self.ast.getNodeConst(id);

        switch (nd) {
            .binop => |v| {
                try self.checkNode(v.lhs);
                try self.checkNode(v.rhs);
                if (self.ast_nodes[v.lhs] == .unknown or self.ast_nodes[v.rhs] == .unknown) {
                    self.unresolved = true;
                    return;
                }
            },
            .unop => |v| {},
            .if_expr => |v| {},
            .let_expr => |v| {},
            .let_entry => |v| {},
            .param => |v| {},
            .reference => |v| {},
            .arg => |v| {},
            .string => |v| {},
            .number => |v| {},
            .unit => |v| {},
            .print => |v| {},
            .println => |v| {},
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
};
