//!
//! Checks for observable behaviour in constant declarations.
//!

const ConstChecker = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Ast = @import("Ast.zig");
const SymbolTable = @import("SymbolTable.zig");
const DiagnosticList = @import("diagnostic").DiagnosticList;

ast: *const Ast,
symtab: *const SymbolTable,
diagnostics: *DiagnosticList,
/// An entry in `links` corresponds to an AST node with the same index.
/// If links[i] is non-null, its value is the index of the AST node that makes AST node with index `i` observable.
links: []?usize,
links_initialized: bool,
change: bool,
allocator: Allocator,

pub fn init(
    ast: *const Ast,
    symtab: *const SymbolTable,
    diagnostics: *DiagnosticList,
    allocator: Allocator,
) !ConstChecker {
    return .{
        .ast = ast,
        .symtab = symtab,
        .diagnostics = diagnostics,
        .links = undefined,
        .links_initialized = false,
        .change = false,
        .allocator = allocator,
    };
}

pub fn deinit(self: *ConstChecker) void {
    if (self.links_initialized) self.allocator.free(self.links);
}

pub fn check(self: *ConstChecker) !void {
    self.links = try self.allocator.alloc(?usize, self.ast.nodes.items.len);
    @memset(self.links, null);
    self.links_initialized = true;

    self.change = true;

    while (self.change) {
        self.change = false;
        self.once();
    }

    try self.accumDiagnostics();
}

fn once(self: *ConstChecker) void {
    // The parser adds children to the node list before its parent,
    // so iterating forward should be the most efficient approach.
    for (self.ast.nodes.items, 0..) |*nd, i| {
        if (self.links[i]) |_| continue;

        switch (nd.*) {
            // IO
            .print, .println => {
                // Link IO to itself.
                self.setLink(i, i);
            },

            // References
            .reference => |v| {
                const symbol = self.symtab.symbols.items[v.symid];

                // For references we add the link to the node instead of propagating the link
                if (self.links[symbol.decl_node_id]) |_| {
                    self.setLink(i, symbol.decl_node_id);
                    continue;
                }

                if (v.args) |args| {
                    if (self.links[args]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .infix => |v| {
                // Same here but with lhs/rhs instead of args
                const symbol = self.symtab.symbols.items[v.symid];

                if (self.links[symbol.decl_node_id]) |_| {
                    self.setLink(i, symbol.decl_node_id);
                    continue;
                }
                if (self.links[v.lhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.rhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },

            // The reset of the node types just propagate links
            .binop => |v| {
                if (self.links[v.lhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.rhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .unop => |v| {
                if (self.links[v.opnd]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .if_expr => |v| {
                if (self.links[v.cond]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.then]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.else_]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .let_expr => |v| {
                if (self.links[v.stmts]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.in]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .let_entry => |v| {
                if (self.links[v.expr]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .arg => |v| {
                if (self.links[v.expr]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (v.next) |next| {
                    if (self.links[next]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .compound => |v| {
                if (self.links[v.discard]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.keep]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .list => |v| {
                if (v.items) |items| {
                    if (self.links[items]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .item => |v| {
                if (self.links[v.expr]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (v.next) |next| {
                    if (self.links[next]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .indexing => |v| {
                if (self.links[v.list]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.index]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .len => |v| {
                if (self.links[v.list]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .struct_ => |v| {
                if (v.fields) |fields| {
                    if (self.links[fields]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .field_access => |v| {
                if (self.links[v.struct_]) |l| {
                    self.setLink(i, l);
                    continue;
                }
            },
            .field_decl => |v| {
                if (self.links[v.expr]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (v.next) |next| {
                    if (self.links[next]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .match => |v| {
                if (self.links[v.expr]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.default]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (v.prongs) |prongs| {
                    if (self.links[prongs]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            .prong => |v| {
                if (self.links[v.lhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (self.links[v.rhs]) |l| {
                    self.setLink(i, l);
                    continue;
                }
                if (v.next) |next| {
                    if (self.links[next]) |l| {
                        self.setLink(i, l);
                        continue;
                    }
                }
            },
            else => {},
        }
    }
}

fn accumDiagnostics(self: *ConstChecker) !void {

    // TODO: add `handled` list to avoid duplicate errors

    for (self.ast.nodes.items, 0..) |*nd, i| {
        if (self.links[i] == null) continue;

        // We are looking for constant declarations
        switch (nd.*) {
            .let_entry => |v| {
                if (v.is_const) {
                    try self.diagnostics.addDiagnostic(.{
                        .description = .{
                            .dynamic = try self.diagnostics.newDynamicDescription(
                                "constant '{s}' has observable behaviour",
                                .{v.name},
                            ),
                        },
                        .location = v.name,
                    });

                    var l: usize = self.links[i].?;
                    while (true) {
                        const next_l = self.links[l].?;

                        const l_nd = &self.ast.nodes.items[l];

                        if (l == next_l) {
                            try self.diagnostics.addRelated(.{
                                .description = .{ .static = "because of this IO operation" },
                                .location = switch (l_nd.*) {
                                    .print => |w| w.tok,
                                    .println => |w| w.tok,
                                    else => unreachable,
                                },
                                .severity = .Hint,
                            });
                            break;
                        } else {
                            // TODO: figure out a way to point to the location of the actual reference
                            try self.diagnostics.addRelated(.{
                                .description = .{ .static = "because of reference to this symbol" },
                                .location = l_nd.let_entry.name,
                                .severity = .Hint,
                            });
                        }

                        l = next_l;
                    }
                }
            },
            else => {},
        }
    }
}

fn setLink(self: *ConstChecker, at: usize, to: usize) void {
    self.links[at] = to;
    self.change = true;
}
