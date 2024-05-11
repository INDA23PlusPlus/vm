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

fn getNode(p: *Parser, i: usize) *Ast.Node {
    return &p.ast.nodes.items[i];
}

fn lastError(p: *Parser) *Error {
    return &p.errors.items[p.errors.items.len - 1];
}

fn expectSomething(p: *Parser, extra: ?[]const u8) !Token {
    return try p.lx.take() orelse {
        try p.errors.append(.{
            .tag = .@"Unexpected end of input",
            .extra = extra,
        });
        return error.ParseError;
    };
}

fn expect(p: *Parser, tag: Token.Tag, extra: ?[]const u8) !Token {
    const tok = try p.expectSomething(extra);
    if (tok.tag != tag) {
        try p.errors.append(.{
            .tag = .@"Unexpected token",
            .where = tok.where,
            .extra = extra,
        });
        return error.ParseError;
    }
    return tok;
}

pub fn parse(p: *Parser) anyerror!void {
    p.ast.root = p.expr() catch |err| switch (err) {
        error.ParseError => 0,
        else => return err,
    };
}

fn expr(p: *Parser) anyerror!usize {
    const tok = try p.lx.peek() orelse {
        try p.errors.append(.{
            .tag = .@"Unexpected end of input",
            .extra = "expected expression",
        });
        return error.ParseError;
    };

    const node = switch (tok.tag) {
        .@"if" => p.ifExpr(),
        .let => p.letExpr(),
        .@" ." => {
            _ = try p.lx.take();
            return p.expr();
        },
        else => p.compound(),
    };

    const next = try p.lx.peek();
    if (next != null and next.?.tag == .@" .") {
        _ = try p.lx.take();
    }

    return node;
}

fn compound(p: *Parser) anyerror!usize {
    var lhs = try p.logic();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"->" => {
                _ = try p.lx.take();
                const rhs = try p.logic();
                lhs = try p.ast.push(.{
                    .compound = .{
                        .discard = lhs,
                        .keep = rhs,
                    },
                });
            },
            else => return lhs,
        }
        tok = try p.lx.peek();
    }
    return lhs;
}

fn logic(p: *Parser) anyerror!usize {
    var lhs = try p.comp();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"and", .@"or" => {
                _ = try p.lx.take();
                const rhs = try p.comp();
                lhs = try p.ast.push(.{
                    .binop = .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = tok_,
                    },
                });
            },
            else => return lhs,
        }
        tok = try p.lx.peek();
    }
    return lhs;
}

fn comp(p: *Parser) anyerror!usize {
    var lhs = try p.sum();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"=", .@"<", .@"<=", .@">", .@">=" => {
                _ = try p.lx.take();
                const rhs = try p.sum();
                lhs = try p.ast.push(.{
                    .binop = .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = tok_,
                    },
                });
            },
            else => return lhs,
        }
        tok = try p.lx.peek();
    }
    return lhs;
}

fn sum(p: *Parser) anyerror!usize {
    var lhs = try p.prod();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"+", .@"-", .@"++" => {
                _ = try p.lx.take();
                const rhs = try p.prod();
                lhs = try p.ast.push(.{
                    .binop = .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = tok_,
                    },
                });
            },
            else => return lhs,
        }
        tok = try p.lx.peek();
    }
    return lhs;
}

fn prod(p: *Parser) anyerror!usize {
    var lhs = try p.fac();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"*", .@"/", .@"%", .@"::" => {
                _ = try p.lx.take();
                const rhs = try p.fac();
                lhs = try p.ast.push(.{
                    .binop = .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = tok_,
                    },
                });
            },
            else => return lhs,
        }
        tok = try p.lx.peek();
    }
    return lhs;
}

fn trailingOperators(p: *Parser, inner: usize) anyerror!usize {
    var inner_ = inner;
    var next_tok = try p.lx.peek() orelse return inner_;

    while (true) {
        switch (next_tok.tag) {
            .@"$" => {
                _ = try p.lx.take();
                // TODO: should index be a whole expression instead of factor?
                const index = try p.fac();
                inner_ = try p.ast.push(.{
                    .indexing = .{
                        .list = inner_,
                        .index = index,
                        .where = next_tok.where,
                    },
                });
            },
            else => break,
        }
        next_tok = try p.lx.peek() orelse return inner_;
    }

    return inner_;
}

fn fac(p: *Parser) anyerror!usize {
    const tok_ = try p.lx.peek();
    if (tok_) |tok| {
        const inner = switch (tok.tag) {
            .@"(" => try p.paren(),
            .@"()" => try p.ast.push(.{ .unit = (try p.lx.take()).? }),
            .string => try p.ast.push(.{ .string = (try p.lx.take()).? }),
            .int, .float => try p.ast.push(.{ .number = (try p.lx.take()).? }),
            .ident => try p.ref(),
            .print => try p.print(),
            .@"[" => try p.list(),
            else => {
                try p.errors.append(.{
                    .tag = .@"Unexpected token",
                    .where = tok.where,
                    .extra = "expected beginning of expression",
                });
                return error.ParseError;
            },
        };

        return p.trailingOperators(inner);
    } else {
        try p.errors.append(.{ .tag = .@"Unexpected end of input" });
        return error.ParseError;
    }
}

fn list(p: *Parser) anyerror!usize {
    const right = (try p.lx.take()).?; // [
    const items_ = try p.items();
    _ = p.expect(.@"]", "missing closing bracket") catch {
        p.lastError().related = right.where;
        p.lastError().related_msg = "opening bracket here";
        return error.ParseError;
    };
    return try p.ast.push(.{ .list = .{ .items = items_ } });
}

fn items(p: *Parser) anyerror!?usize {
    const tok = try p.lx.peek() orelse return null;
    if (tok.tag == .@"]") {
        return null;
    } else {
        const expr_ = try p.expr();
        const item = try p.ast.push(.{
            .item = .{
                .expr = expr_,
                .next = null,
            },
        });
        const next_tok = try p.lx.peek();
        if (next_tok != null and next_tok.?.tag == .@",") {
            _ = try p.lx.take(); // ,
            p.ast.getNode(item).item.next = try p.items();
        }
        return item;
    }
}

fn print(p: *Parser) anyerror!usize {
    _ = try p.lx.take(); // print
    return try p.ast.push(.{ .print = try p.expr() });
}

fn isExprBegin(tok: Token) bool {
    return switch (tok.tag) {
        .@"(",
        .@"()",
        .ident,
        .int,
        .float,
        .string,
        => true,
        else => false,
    };
}

fn ref(p: *Parser) anyerror!usize {
    const name = try p.lx.take();
    const args_ = try p.args();
    return p.ast.push(.{
        .reference = .{
            .name = name.?.where,
            .args = args_,
        },
    });
}

fn args(p: *Parser) anyerror!?usize {
    const tok = try p.lx.peek();
    if (tok != null and isExprBegin(tok.?)) {
        return try p.ast.push(.{
            .arg = .{
                .expr = try p.expr(),
                .next = try p.args(),
            },
        });
    } else return null;
}

fn paren(p: *Parser) anyerror!usize {
    const left = (try p.lx.take()).?;
    const expr_ = try p.expr();
    _ = p.expect(.@")", "missing closing parenthesis") catch {
        p.lastError().related = left.where;
        p.lastError().related_msg = "opening parenthesis here";
        return error.ParseError;
    };
    return expr_;
}

fn ifExpr(p: *Parser) anyerror!usize {
    _ = try p.lx.take(); // if
    const cond = try p.expr();
    _ = try p.expect(.then, "expected 'then'");
    const then = try p.expr();
    _ = try p.expect(.@"else", "expected 'else'");
    const else_ = try p.expr();
    return try p.ast.push(.{
        .if_expr = .{
            .cond = cond,
            .then = then,
            .else_ = else_,
        },
    });
}

fn letExpr(p: *Parser) !usize {
    _ = try p.lx.take(); // let

    var entry = try p.letEntry();
    const root = entry;

    var tok = try p.lx.peek();
    while (tok != null and tok.?.tag != .in) {
        const next = try p.letEntry();
        p.getNode(entry).let_entry.next = next;
        entry = next;
        tok = try p.lx.peek();
    }

    _ = try p.expect(.in, "expected 'in'");
    const expr_ = try p.expr();

    return p.ast.push(.{
        .let_expr = .{
            .stmts = root,
            .in = expr_,
        },
    });
}

fn letEntry(p: *Parser) !usize {
    const name = try p.expect(.ident, "expected identifier");
    const params_ = try p.params();
    const assign = try p.expect(.@"=", "expected '='");
    const expr_ = try p.expr();
    _ = try p.expect(.@";", "expected semicolon");
    return try p.ast.push(.{
        .let_entry = .{
            .name = name.where,
            .params = params_,
            .expr = expr_,
            .assign_where = assign.where,
        },
    });
}

fn params(p: *Parser) !?usize {
    const tok = try p.lx.peek();
    if (tok != null and tok.?.tag == .ident) {
        _ = try p.lx.take();
        return try p.ast.push(.{
            .param = .{
                .name = tok.?.where,
                .next = try p.params(),
            },
        });
    }
    return null;
}
