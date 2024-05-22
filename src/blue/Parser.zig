//!
//! Parser for Blue language.
//!
const Parser = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const Token = @import("Token.zig");
const Lexer = Token.Lexer;
const Ast = @import("Ast.zig");

const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

ast: *Ast,
lx: *Lexer,
diagnostics: *DiagnosticList,

pub fn init(ast: *Ast, lexer: *Lexer, diagnostics: *DiagnosticList) Parser {
    return .{
        .ast = ast,
        .lx = lexer,
        .diagnostics = diagnostics,
    };
}

pub fn deinit(p: *Parser) void {
    // nothing to do here
    _ = p;
}

fn getNode(p: *Parser, i: usize) *Ast.Node {
    return &p.ast.nodes.items[i];
}

fn expectSomething(p: *Parser, extra: ?[]const u8) !Token {
    const tok = try p.expectSomethingPeek(extra);
    _ = try p.lx.take();
    return tok;
}

fn expectSomethingPeek(p: *Parser, extra: ?[]const u8) !Token {
    return try p.lx.peek() orelse {
        const description: diagnostic.Description = if (extra) |extra_| .{
            .dynamic = try p.diagnostics.newDynamicDescription(
                "unexpected end of input, {s}",
                .{extra_},
            ),
        } else .{ .static = "unexpected end of input" };
        try p.diagnostics.addDiagnostic(.{
            .description = description,
        });
        return error.ParseError;
    };
}

fn expect(p: *Parser, tag: Token.Tag, extra: ?[]const u8) !Token {
    const tok = try p.expectPeek(tag, extra);
    _ = try p.lx.take();
    return tok;
}

fn expectPeek(p: *Parser, tag: Token.Tag, extra: ?[]const u8) !Token {
    const tok = try p.expectSomethingPeek(extra);
    if (tok.tag != tag) {
        const description: diagnostic.Description = if (extra) |extra_| .{
            .dynamic = try p.diagnostics.newDynamicDescription(
                "unexpected token \"{s}\", {s}",
                .{ tok.where, extra_ },
            ),
        } else .{
            .dynamic = try p.diagnostics.newDynamicDescription(
                "unexpected token \"{s}\"",
                .{tok.where},
            ),
        };
        try p.diagnostics.addDiagnostic(.{
            .description = description,
            .location = tok.where,
        });
        return error.ParseError;
    }
    return tok;
}

pub fn parse(p: *Parser) anyerror!void {
    p.ast.root = p.expr() catch |err| switch (err) {
        error.ParseError => {
            p.ast.root = 0;
            return;
        },
        else => return err,
    };

    if (try p.lx.peek()) |trail| {
        try p.diagnostics.addDiagnostic(.{
            .description = .{
                .dynamic = try p.diagnostics.newDynamicDescription(
                    "trailing token(s) \"{s}...\"",
                    .{trail.where},
                ),
            },
            .location = trail.where,
            .severity = .Warning,
        });
    }
}

fn expr(p: *Parser) anyerror!usize {
    const node = p.compound();

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
            .@"=", .@"!=", .@"<", .@"<=", .@">", .@">=" => {
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
    var lhs = try p.infix();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .@"*", .@"/", .@"%", .@"::" => {
                _ = try p.lx.take();
                const rhs = try p.infix();
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

fn infix(p: *Parser) anyerror!usize {
    var lhs = try p.fac();
    var tok = try p.lx.peek();

    while (tok) |tok_| {
        switch (tok_.tag) {
            .infix => {
                _ = try p.lx.take();
                const rhs = try p.fac();
                lhs = try p.ast.push(.{
                    .infix = .{
                        .lhs = lhs,
                        .rhs = rhs,
                        .name = tok_.where,
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
            .@"." => {
                _ = try p.lx.take();
                const field_ = try p.expect(.ident, "expected field name");
                inner_ = try p.ast.push(.{
                    .field_access = .{
                        .struct_ = inner_,
                        .field = field_.where,
                        .dot = next_tok.where,
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
            .println => try p.println(),
            .len => try p.len(),
            .@"[" => try p.list(),
            .@"if" => try p.ifExpr(),
            .let => try p.letExpr(),
            .@"{" => try p.struct_(),
            .match => try p.match(),
            .neg => try p.neg(),
            else => {
                try p.diagnostics.addDiagnostic(.{
                    .description = .{
                        .dynamic = try p.diagnostics.newDynamicDescription(
                            "unexpected token \"{s}\"",
                            .{tok.where},
                        ),
                    },
                    .location = tok.where,
                });
                return error.ParseError;
            },
        };

        return p.trailingOperators(inner);
    } else {
        try p.diagnostics.addDiagnostic(.{
            .description = .{ .static = "unexpected end of input, expected expression" },
        });
        return error.ParseError;
    }
}

fn neg(p: *Parser) anyerror!usize {
    const neg_ = (try p.lx.take()).?;
    const fac_ = try p.fac();
    return try p.ast.push(.{
        .unop = .{
            .opnd = fac_,
            .op = neg_,
        },
    });
}

fn match(p: *Parser) anyerror!usize {
    const match_tok = (try p.lx.take()).?;
    const expr_ = try p.expr();
    _ = try p.expect(.with, "expected 'with'");

    const optional_pipe = try p.lx.peek() orelse {
        try p.diagnostics.addDiagnostic(.{
            .description = .{ .static = "unexpected end of input, expected match prong" },
            .location = p.lx.src[p.lx.src.len - 1 ..],
        });
        return error.ParseError;
    };
    if (optional_pipe.tag == .@"|") {
        _ = try p.lx.take();
    }

    var default: ?usize = null;
    var first_default_where: []const u8 = undefined;

    var root_prong: ?usize = null;
    var curr_prong: usize = undefined;

    while (true) {
        const prong_begin = try p.lx.peek() orelse break;
        if (prong_begin.tag == ._) {
            _ = try p.lx.take(); // _
            _ = try p.expect(.@"=>", "expected '=>'");
            const def_expr = try p.expr();

            if (default) |_| {
                try p.diagnostics.addDiagnostic(.{
                    .description = .{ .static = "duplicate default prong" },
                    .location = prong_begin.where,
                });
                try p.diagnostics.addRelated(.{
                    .description = .{ .static = "first default appears here" },
                    .location = first_default_where,
                    .severity = .Hint,
                });
            } else {
                default = def_expr;
                first_default_where = prong_begin.where;
            }
        } else {
            const next_prong = try p.prong();
            if (root_prong == null) {
                root_prong = next_prong;
                curr_prong = next_prong;
            } else {
                p.ast.getNode(curr_prong).prong.next = next_prong;
                curr_prong = next_prong;
            }
        }

        const maybe_pipe = try p.lx.peek() orelse break;
        if (maybe_pipe.tag != .@"|") break;
        _ = try p.lx.take(); // |
    }

    if (default == null) {
        default = 0; // dummy value
        try p.diagnostics.addDiagnostic(.{
            .description = .{ .static = "this match expression is missing the default prong '_ => ...'" },
            .location = match_tok.where,
        });
    }

    return p.ast.push(.{
        .match = .{
            .expr = expr_,
            .prongs = root_prong,
            .default = default.?,
        },
    });
}

fn prong(p: *Parser) anyerror!usize {
    const lhs = try p.expr();
    const arrow = try p.expect(.@"=>", "expected '=>'");
    const rhs = try p.expr();
    return p.ast.push(.{
        .prong = .{
            .lhs = lhs,
            .rhs = rhs,
            .next = null,
            .where = arrow.where,
        },
    });
}

fn struct_(p: *Parser) anyerror!usize {
    const left = (try p.lx.take()).?; // {
    const fields_ = p.fields() catch {
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "in initalization of this struct" },
            .location = left.where,
            .severity = .Hint,
        });
        return error.ParseError;
    };
    _ = p.expect(.@"}", "missing closing bracket") catch {
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "opening bracket here" },
            .location = left.where,
            .severity = .Hint,
        });
        return error.ParseError;
    };
    return try p.ast.push(.{ .struct_ = .{ .leading_brc = left.where, .fields = fields_ } });
}

fn list(p: *Parser) anyerror!usize {
    const left = (try p.lx.take()).?; // [
    const items_ = p.items() catch {
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "in initalization of this list" },
            .location = left.where,
            .severity = .Hint,
        });
        return error.ParseError;
    };
    _ = p.expect(.@"]", "missing closing bracket") catch {
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "opening bracket here" },
            .location = left.where,
            .severity = .Hint,
        });
        return error.ParseError;
    };
    return try p.ast.push(.{ .list = .{ .leading_brk = left.where, .items = items_ } });
}

fn fields(p: *Parser) anyerror!?usize {
    var tok = try p.lx.peek() orelse return null;
    if (tok.tag == .@"}") return null;
    const root = try p.field();
    var field_ = root;
    while (true) {
        tok = try p.lx.peek() orelse return root;
        if (tok.tag == .@"}") return root;
        _ = try p.expect(.@",", "expected ','");
        tok = try p.lx.peek() orelse return root;
        if (tok.tag == .@"}") return root;
        const next = try p.field();
        p.ast.getNode(field_).field_decl.next = next;
        field_ = next;
    }
}

fn field(p: *Parser) anyerror!usize {
    const name = try p.expect(.ident, "expected field name");

    const next_tok = try p.lx.peek() orelse {
        try p.diagnostics.addDiagnostic(.{
            .description = .{ .static = "unexpected end of input, expected '}'" },
            .location = p.lx.src[p.lx.src.len - 1 ..],
        });
        return error.ParseError;
    };

    switch (next_tok.tag) {
        .@"=" => {
            _ = try p.lx.take(); // =
            const expr_ = try p.expr();
            return try p.ast.push(.{
                .field_decl = .{
                    .name = name.where,
                    .expr = expr_,
                    .next = null,
                },
            });
        },
        .@",", .@"}" => {
            const ref_ = try p.ast.push(.{
                .reference = .{
                    .name = name.where,
                    .args = null,
                },
            });
            return try p.ast.push(.{
                .field_decl = .{
                    .name = name.where,
                    .expr = ref_,
                    .next = null,
                },
            });
        },
        else => {
            try p.diagnostics.addDiagnostic(.{
                .description = .{
                    .dynamic = try p.diagnostics.newDynamicDescription(
                        "unexpected token \"{s}\", expected '=', ',' or '}}'",
                        .{next_tok.where},
                    ),
                },
                .location = next_tok.where,
            });
            return error.ParseError;
        },
    }
}

fn items(p: *Parser) anyerror!?usize {
    var tok = try p.lx.peek() orelse return null;
    if (tok.tag == .@"]") return null;
    const root = try p.item();
    var item_ = root;
    while (true) {
        tok = try p.lx.peek() orelse return root;
        if (tok.tag == .@"]") return root;
        _ = try p.expect(.@",", "expected ','");
        tok = try p.lx.peek() orelse return root;
        if (tok.tag == .@"]") return root;
        const next = try p.item();
        p.ast.getNode(item_).item.next = next;
        item_ = next;
    }
}

fn item(p: *Parser) anyerror!usize {
    const expr_ = try p.expr();
    return try p.ast.push(.{
        .item = .{
            .expr = expr_,
            .next = null,
        },
    });
}

fn print(p: *Parser) anyerror!usize {
    _ = try p.lx.take(); // print
    return try p.ast.push(.{ .print = try p.expr() });
}

fn println(p: *Parser) anyerror!usize {
    _ = try p.lx.take(); // print
    return try p.ast.push(.{ .println = try p.expr() });
}

fn len(p: *Parser) anyerror!usize {
    const tok = (try p.lx.take()).?; // print
    return try p.ast.push(.{
        .len = .{
            .list = try p.expr(),
            .where = tok.where,
        },
    });
}

fn isExprBegin(tok: Token) bool {
    return switch (tok.tag) {
        .@"(",
        .@"()",
        .ident,
        .int,
        .float,
        .string,
        .len,
        .@"[",
        .@"if",
        .@"{",
        .match,
        .neg,
        .print,
        .println,
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
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "opening parenthesis here" },
            .location = left.where,
            .severity = .Hint,
        });
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
    const maybe_const = try p.expectSomethingPeek("expected 'const' or identfier");
    const is_const = if (maybe_const.tag == .@"const") blk: {
        _ = try p.lx.take();
        break :blk true;
    } else false;
    const name = try p.expect(.ident, "expected identifier");
    const params_ = try p.params();
    if (is_const and params_ != null) {
        try p.diagnostics.addDiagnostic(.{
            .description = .{ .static = "redundant 'const' specifier for function" },
            .location = maybe_const.where,
            .severity = .Warning,
        });
    }
    const assign = try p.expect(.@"=", "expected '='");
    const expr_ = try p.expr();
    _ = p.expect(.@";", "expected semicolon") catch {
        try p.diagnostics.addRelated(.{
            .description = .{ .static = "expression following this '=' needs to be terminated with ';'" },
            .location = assign.where,
            .severity = .Hint,
        });
        return error.ParseError;
    };
    return try p.ast.push(.{
        .let_entry = .{
            .name = name.where,
            .params = params_,
            .expr = expr_,
            .assign_where = assign.where,
            .is_const = is_const or params_ != null,
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
