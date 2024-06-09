//!
//! Module for compiling the Blue language
//!

pub const Token = @import("Token.zig");
pub const Ast = @import("Ast.zig");
pub const Parser = @import("Parser.zig");
pub const SymbolTable = @import("SymbolTable.zig");
pub const CodeGen = @import("CodeGen.zig");

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

pub const Compilation = struct {
    result: []const u8,
    source: []const u8,
    tokens: [][]const u8,
    // private fields
    _ast: Ast,
    _lexer: Token.Lexer,
    _parser: Parser,
    _symtab: SymbolTable,
    _codegen: ?CodeGen,

    pub fn deinit(self: *Compilation) void {
        self._ast.deinit();
        self._lexer.deinit();
        self._parser.deinit();
        self._symtab.deinit();
        if (self._codegen) |*cg| cg.deinit();
    }
};

pub fn compile(
    source: []const u8,
    allocator: Allocator,
    diagnostics: *DiagnosticList,
    only_check: bool,
    comptime ast_overlay: ?fn (*Ast) anyerror!void,
) !Compilation {
    var comp: Compilation = undefined;
    comp.source = source;
    comp._lexer = Token.Lexer.init(source, diagnostics);
    comp._ast = Ast.init(allocator);
    comp._parser = Parser.init(&comp._ast, &comp._lexer, diagnostics);
    errdefer comp._lexer.deinit();
    errdefer comp._ast.deinit();
    errdefer comp._parser.deinit();
    try comp._parser.parse();
    if (ast_overlay) |overlay| try overlay(&comp._ast);
    if (diagnostics.hasDiagnosticsMinSeverity(.Error)) return error.CompilationError;
    comp._symtab = try SymbolTable.init(allocator, &comp._ast, diagnostics);
    errdefer comp._symtab.deinit();
    try comp._symtab.resolve();
    try comp._symtab.checkUnused();
    if (diagnostics.hasDiagnosticsMinSeverity(.Error)) return error.CompilationError;
    if (only_check) {
        comp._codegen = null;
        return comp;
    }
    comp._codegen = CodeGen.init(&comp._ast, &comp._symtab, source, allocator);
    errdefer comp._codegen.?.deinit();
    try comp._codegen.?.gen();
    comp.result = comp._codegen.?.code.items;
    comp.tokens = comp._codegen.?.instr_toks.items;
    return comp;
}

test {
    _ = @import("Token.zig");
}
