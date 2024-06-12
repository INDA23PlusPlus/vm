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

                _ = self.propLink(i, v.args);
            },
            .infix => |v| {
                // Same here but with lhs/rhs instead of args
                const symbol = self.symtab.symbols.items[v.symid];

                if (self.links[symbol.decl_node_id]) |_| {
                    self.setLink(i, symbol.decl_node_id);
                    continue;
                }

                _ = self.propLink(i, v.lhs) or self.propLink(i, v.rhs);
            },

            // The rest of the node types just propagate links
            .binop => |v| _ = self.propLink(i, v.lhs) or self.propLink(i, v.rhs),
            .unop => |v| _ = self.propLink(i, v.opnd),
            .if_expr => |v| _ = self.propLink(i, v.cond) or self.propLink(i, v.then) or self.propLink(i, v.else_),
            .let_expr => |v| _ = self.propLink(i, v.stmts) or self.propLink(i, v.in),
            .let_entry => |v| _ = self.propLink(i, v.expr),
            .arg => |v| _ = self.propLink(i, v.expr) or self.propLink(i, v.next),
            .compound => |v| _ = self.propLink(i, v.discard) or self.propLink(i, v.keep),
            .list => |v| _ = self.propLink(i, v.items),
            .item => |v| _ = self.propLink(i, v.expr) or self.propLink(i, v.next),
            .indexing => |v| _ = self.propLink(i, v.list) or self.propLink(i, v.index),
            .len => |v| _ = self.propLink(i, v.list),
            .struct_ => |v| _ = self.propLink(i, v.fields),
            .field_access => |v| _ = self.propLink(i, v.struct_),
            .field_decl => |v| _ = self.propLink(i, v.expr) or self.propLink(i, v.next),
            .match => |v| _ = self.propLink(i, v.expr) or self.propLink(i, v.default) or self.propLink(i, v.prongs),
            .prong => |v| _ = self.propLink(i, v.lhs) or self.propLink(i, v.rhs) or self.propLink(i, v.next),
            else => {},
        }
    }
}

fn setLink(self: *ConstChecker, at: usize, to: usize) void {
    self.links[at] = to;
    self.change = true;
}

fn propLink(self: *ConstChecker, dst: usize, src: anytype) bool {
    const src_ = if (@TypeOf(src) == usize) src else src orelse return false;
    if (self.links[src_]) |l| {
        self.links[dst] = l;
        self.change = true;
        return true;
    } else return false;
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
