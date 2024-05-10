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
const Error = @import("asm").Error;

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
    errors: *ArrayList(Error),
    only_check: bool,
) !Compilation {
    var comp: Compilation = undefined;
    comp.source = source;
    comp._lexer = Token.Lexer.init(source, errors);
    comp._ast = Ast.init(allocator);
    comp._parser = Parser.init(&comp._ast, &comp._lexer, errors);
    errdefer comp._lexer.deinit();
    errdefer comp._ast.deinit();
    errdefer comp._parser.deinit();
    try comp._parser.parse();
    if (errors.items.len > 0) return error.CompilationError;
    comp._symtab = try SymbolTable.init(allocator, &comp._ast, errors);
    errdefer comp._symtab.deinit();
    try comp._symtab.resolve();
    if (errors.items.len > 0) return error.CompilationError;
    if (only_check) {
        comp._codegen = null;
        return comp;
    }
    comp._codegen = CodeGen.init(&comp._ast, &comp._symtab, source, errors, allocator);
    errdefer comp._codegen.?.deinit();
    try comp._codegen.?.gen();
    if (errors.items.len > 0) return error.CompilationError;
    comp.result = comp._codegen.?.code.items;
    comp.tokens = comp._codegen.?.instr_toks.items;
    return comp;
}

test {
    _ = @import("Token.zig");
}
