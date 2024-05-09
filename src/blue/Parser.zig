//!
//! Parser for Blue language.
//!
const Parser = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const Error = @import("asm").Error;
const Token = @import("Token.zig");
const Lexer = Token.Lexer;
const Ast = @import("Ast.zig");

ast: *Ast,
lx: *Lexer,
errors: *ArrayList(Error),

pub fn init(ast: *Ast, lexer: *Lexer, errors: *ArrayList(Error)) Parser {
    return .{
        .ast = ast,
        .lx = lexer,
        .errors = errors,
    };
}

pub fn deinit(p: *Parser) void {
    // nothing to do here
    _ = p;
}

fn expectExtra(p: *Parser, tag: Token.Tag, extra: ?[]const u8) !Token {
    const tok = p.lx.take();
    if (tok.tag != tag) {
        try p.errors.append(.{
            .tag = .@"Unexpected token",
            .where = tok.were,
            .extra = extra,
        });
        return error.ParseError;
    }
    return tok;
}

fn expect(p: *Parser, tag: Token.Tag) !Token {
    return p.expextExtra(tag, null);
}
