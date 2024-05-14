//!
//! Symbol resolution for Blue language.
//!
const SymbolTable = @This();
const std = @import("std");
const Scope = std.StringHashMap(usize);
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Ast = @import("Ast.zig");
const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

pub const SymbolKind = union(enum) {
    func: usize,
    param: usize,
    local: usize,
};

pub const Symbol = struct {
    decl_loc: []const u8,
    nparams: usize,
    kind: SymbolKind,
    is_const: bool,
};

const ScopeIterator = struct {
    table: *const SymbolTable,
    index: usize,
    done: bool = false,
    only_consts: bool = false,

    pub fn init(table: *const SymbolTable) ScopeIterator {
        return .{
            .table = table,
            .index = table.currentScopeID(),
        };
    }

    pub fn next(self: *ScopeIterator) ?*Scope {
        if (self.done) return null;
        const marker = self.table.topMarker();
        if (marker != null and marker.? == self.index) self.only_consts = true;
        const scope = &self.table.scopes.items[self.index];
        if (self.index == 0) self.done = true else self.index -= 1;
        return scope;
    }
};

scopes: ArrayList(Scope),
symbols: ArrayList(Symbol),
ast: *Ast,
diagnostics: *DiagnosticList,
allocator: Allocator,
// We don't allow captures. Therefore the only symbols
// that should be available in a function scope outside of that scope,
// is other functions. The markers are pushed when we enter a funciton scope.
markers: ArrayList(usize),
param_counter: usize,
local_counters: ArrayList(usize),

pub fn init(allocator: Allocator, ast: *Ast, diagnostics: *DiagnosticList) !SymbolTable {
    var self = SymbolTable{
        .scopes = ArrayList(Scope).init(allocator),
        .symbols = ArrayList(Symbol).init(allocator),
        .ast = ast,
        .diagnostics = diagnostics,
        .allocator = allocator,
        .markers = ArrayList(usize).init(allocator),
        .param_counter = 0,
        .local_counters = ArrayList(usize).init(allocator),
    };
    try self.pushScope();
    try self.pushLocalCounter();
    return self;
}

pub fn deinit(self: *SymbolTable) void {
    for (self.scopes.items) |*scope| scope.deinit();
    self.scopes.deinit();
    self.symbols.deinit();
    self.markers.deinit();
    self.local_counters.deinit();
}

pub fn resolve(self: *SymbolTable) !void {
    self.resolveNode(self.ast.root) catch |err| switch (err) {
        else => return err,
    };
}

pub fn getSymbol(self: *SymbolTable, id: usize) *Symbol {
    return &self.symbols.items[id];
}

fn currentScopeID(self: *const SymbolTable) usize {
    std.debug.assert(self.scopes.items.len > 0);
    return self.scopes.items.len - 1;
}

fn pushScope(self: *SymbolTable) !void {
    try self.scopes.append(Scope.init(self.allocator));
}

fn popScope(self: *SymbolTable) void {
    var scope = self.scopes.pop();
    scope.deinit();
}

fn pushMarkerForThisScope(self: *SymbolTable) !void {
    try self.markers.append(self.currentScopeID());
}

fn popMarker(self: *SymbolTable) void {
    _ = self.markers.pop();
}

fn topMarker(self: *const SymbolTable) ?usize {
    return self.markers.getLastOrNull();
}

fn newSymbol(self: *SymbolTable) !usize {
    _ = try self.symbols.addOne();
    return self.symbols.items.len - 1;
}

fn nextParamID(self: *SymbolTable) usize {
    defer self.param_counter += 1;
    return self.param_counter;
}

fn nextLocalID(self: *SymbolTable) usize {
    const ptr = &self.local_counters.items[self.local_counters.items.len - 1];
    defer ptr.* += 1;
    return ptr.*;
}

fn resetParamCounter(self: *SymbolTable) void {
    self.param_counter = 0;
}

fn pushLocalCounter(self: *SymbolTable) !void {
    try self.local_counters.append(0);
}

fn popLocalCounter(self: *SymbolTable) void {
    _ = self.local_counters.pop();
}

fn currentLocalCounter(self: *SymbolTable) usize {
    return self.local_counters.getLast();
}

pub fn mainLocalCount(self: *SymbolTable) usize {
    return self.local_counters.items[0];
}

fn reference(self: *SymbolTable, name: []const u8, nparams: usize) !usize {
    var scope_iter = ScopeIterator.init(self);
    while (scope_iter.next()) |scope| {
        if (scope.get(name)) |symid| {
            const symbol = &self.symbols.items[symid];
            if (!symbol.is_const and scope_iter.only_consts) {
                try self.diagnostics.addDiagnostic(.{
                    .description = .{
                        .dynamic = try self.diagnostics.newDynamicDescription(
                            "reference of external non-constant \"{s}\"",
                            .{name},
                        ),
                    },
                    .location = name,
                });
                try self.diagnostics.addRelated(.{
                    .description = .{ .static = "non-constant declared here" },
                    .location = symbol.decl_loc,
                    .severity = .Hint,
                });
            }
            if (symbol.nparams != nparams) {
                try self.diagnostics.addDiagnostic(.{
                    .description = .{
                        .dynamic = try self.diagnostics.newDynamicDescription(
                            "argument count mismatch, \"{s}\" takes {d} parameters but {d} where provided",
                            .{ name, symbol.nparams, nparams },
                        ),
                    },
                    .location = name,
                });
                try self.diagnostics.addRelated(.{
                    .description = .{
                        .dynamic = try self.diagnostics.newDynamicDescription(
                            "\"{s}\" declared here",
                            .{symbol.decl_loc},
                        ),
                    },
                    .location = symbol.decl_loc,
                    .severity = .Hint,
                });
                return 0;
            } else {
                return symid;
            }
        }
    } else {
        try self.diagnostics.addDiagnostic(.{
            .description = .{
                .dynamic = try self.diagnostics.newDynamicDescription("unresolved symbol \"{s}\"", .{name}),
            },
            .location = name,
        });
        return 0;
    }
}

fn declare(self: *SymbolTable, name: []const u8, nparams: usize, kind: SymbolKind, is_const: bool) !usize {
    var scope = self.scopes.items[self.currentScopeID()];
    if (scope.get(name)) |symid| {
        const symbol = &self.symbols.items[symid];
        try self.diagnostics.addDiagnostic(.{
            .description = .{
                .dynamic = try self.diagnostics.newDynamicDescription(
                    "duplicate symbol \"{s}\"",
                    .{name},
                ),
            },
            .location = name,
        });
        try self.diagnostics.addRelated(.{
            .description = .{ .static = "previously declared here" },
            .location = symbol.decl_loc,
            .severity = .Hint,
        });
        return 0;
    } else {
        const symid = try self.newSymbol();
        const symbol = &self.symbols.items[symid];
        symbol.decl_loc = name;
        symbol.nparams = nparams;
        symbol.kind = kind;
        symbol.is_const = is_const;
        try self.scopes.items[self.currentScopeID()].put(name, symid);
        return symid;
    }
}

fn countChildren(self: *SymbolTable, node_id: usize) usize {
    const node = self.ast.nodes.items[node_id];
    return switch (node) {
        .reference => |v| if (v.args) |args| 1 + self.countChildren(args) else 0,
        .let_entry => |v| if (v.params) |params| 1 + self.countChildren(params) else 0,
        .arg => |v| if (v.next) |next| 1 + self.countChildren(next) else 0,
        .param => |v| if (v.next) |next| 1 + self.countChildren(next) else 0,
        else => unreachable,
    };
}

fn resolveNode(self: *SymbolTable, node_id: usize) !void {
    const node = &self.ast.nodes.items[node_id];

    switch (node.*) {
        .binop => |v| {
            try self.resolveNode(v.lhs);
            try self.resolveNode(v.rhs);
        },
        .unop => |v| {
            try self.resolveNode(v.opnd);
        },
        .if_expr => |v| {
            try self.resolveNode(v.cond);
            try self.resolveNode(v.then);
            try self.resolveNode(v.else_);
        },
        .let_expr => |v| {
            try self.pushScope();
            try self.resolveNode(v.stmts);
            try self.resolveNode(v.in);
            self.popScope();
        },
        .let_entry => |*v| {
            // Declare the symbol with number of params (may be zero).
            const nparams = self.countChildren(node_id);
            // This is where constants are turned in to zero parameter functions!
            const kind: SymbolKind = if (nparams > 0 or v.is_const) .{
                .func = undefined,
            } else .{
                .local = self.nextLocalID(),
            };

            // Only let symbol reference itself if it's a REAL function
            if (nparams > 0) {
                v.symid = try self.declare(v.name, nparams, kind, true);
            }

            // Push new scope for params and expression,
            // as well as a marker if there are more than zero markers.
            if (kind == .func) try self.pushMarkerForThisScope();
            try self.pushScope();

            // Resolve params and reset param counter.
            if (v.params) |params| try self.resolveNode(params);
            self.resetParamCounter();

            // If this is a function, create new local counter.
            if (nparams > 0) try self.pushLocalCounter();
            try self.resolveNode(v.expr);
            if (nparams > 0) {
                self.symbols.items[v.symid].kind.func = self.currentLocalCounter();
                self.popLocalCounter();
            }

            // Exit scope, remove marker if it exists.
            self.popScope();
            if (kind == .func) self.popMarker();

            // If symbol is not a REAL function, declare it after we've
            // resolved it's definition.
            if (nparams == 0) {
                v.symid = try self.declare(v.name, nparams, kind, v.is_const);
            }

            // Resolve next entry in let expression.
            if (v.next) |next| try self.resolveNode(next);
        },
        .param => |*v| {
            v.symid = try self.declare(v.name, 0, .{ .param = self.nextParamID() }, false);
            if (v.next) |next| try self.resolveNode(next);
        },
        .reference => |*v| {
            const nparams = self.countChildren(node_id);
            v.symid = try self.reference(v.name, nparams);
            if (v.args) |args| try self.resolveNode(args);
        },
        .infix => |*v| {
            v.symid = try self.reference(v.name, 2);
            try self.resolveNode(v.lhs);
            try self.resolveNode(v.rhs);
        },
        .arg => |*v| {
            try self.resolveNode(v.expr);
            if (v.next) |next| try self.resolveNode(next);
        },
        .print => |v| try self.resolveNode(v),
        .compound => |v| {
            try self.resolveNode(v.discard);
            try self.resolveNode(v.keep);
        },
        .list => |v| if (v.items) |items| try self.resolveNode(items),
        .item => |v| {
            try self.resolveNode(v.expr);
            if (v.next) |next| try self.resolveNode(next);
        },
        .indexing => |v| {
            try self.resolveNode(v.list);
            try self.resolveNode(v.index);
        },
        .len => |v| try self.resolveNode(v.list),
        .struct_ => |v| if (v.fields) |fields| try self.resolveNode(fields),
        .field_access => |v| try self.resolveNode(v.struct_),
        .field_decl => |v| {
            try self.resolveNode(v.expr);
            if (v.next) |next| try self.resolveNode(next);
        },
        .match => |v| {
            try self.resolveNode(v.expr);
            try self.resolveNode(v.default);
            if (v.prongs) |prongs| try self.resolveNode(prongs);
        },
        .prong => |v| {
            try self.resolveNode(v.lhs);
            try self.resolveNode(v.rhs);
            if (v.next) |next| try self.resolveNode(next);
        },
        // don't use 'else' prong, so newly added
        // node types aren't silentlty ignored
        .string,
        .number,
        .unit,
        => {},
    }
}

pub fn dump(self: *SymbolTable, writer: anytype) !void {
    for (self.symbols.items, 0..) |symbol, i| {
        try writer.print("{d}: \"{s}\", {d}, {s}\n", .{
            i,
            symbol.decl_loc,
            symbol.nparams,
            @tagName(symbol.kind),
        });
    }
}
