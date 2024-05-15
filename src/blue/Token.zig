//!
//! Blue tokens and lexer.
//!
const Token = @This();
const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const ArrayList = std.ArrayList;
const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

pub const Tag = enum {
    let,
    in,
    @"if",
    then,
    @"else",
    @"and",
    @"or",
    println,
    print,
    @"_",
    @"=",
    @"=>",
    @"<",
    @"<=",
    @">",
    @">=",
    @"!",
    @"!=",
    @"+",
    @"++",
    @":",
    @"::",
    @"-",
    @"*",
    @"/",
    @"%",
    @"(",
    @")",
    @"()",
    @"[",
    @"]",
    @"{",
    @"}",
    @"|",
    @"->",
    @";",
    @",",
    @".",
    @" .",
    @"$",
    neg,
    string,
    int,
    len,
    float,
    ident,
    infix,
    match,
    with,
    err,
    @"const",
};

const kws: []const Tag = &.{ .let, .in, .@"if", .then, .@"else", .print, .len, .match, .with, .@"and", .@"or", .@"const", .println };

tag: Tag,
where: []const u8,

pub const Lexer = struct {
    src: []const u8,
    pos: usize = 0,
    peeked: ?Token = null,
    diagnostics: *DiagnosticList,

    pub fn init(src: []const u8, diagnostics: *DiagnosticList) Lexer {
        return .{ .src = src, .diagnostics = diagnostics };
    }

    pub fn deinit(self: *Lexer) void {
        // nothing to do here
        _ = self;
    }

    pub fn take(self: *Lexer) !?Token {
        const tok = try self.take_();
        if (tok == null) return null;
        return tok;
    }

    pub fn take_(self: *Lexer) !?Token {
        if (self.peeked) |peeked| {
            defer self.peeked = null;
            return peeked;
        }

        while (self.skipWhitespace() or self.skipComments()) {}
        if (self.curr() == null) return null;

        if (self.operator()) |tok| return tok;
        if (self.identOrKw()) |tok| return tok;
        if (try self.string()) |tok| return tok;
        if (self.number()) |tok| return tok;
        if (try self.infix()) |tok| return tok;

        const where = self.src[self.pos .. self.pos + 1];
        try self.diagnostics.addDiagnostic(.{
            .description = .{
                .dynamic = try self.diagnostics.newDynamicDescription(
                    "invalid character \'{c}\'",
                    .{self.curr().?},
                ),
            },
            .location = where,
        });
        self.adv();
        return .{ .tag = .err, .where = where };
    }

    pub fn peek(self: *Lexer) !?Token {
        const tok = try self.peek_();
        if (tok == null) return null;
        return tok;
    }

    pub fn peek_(self: *Lexer) !?Token {
        if (self.peeked == null) {
            self.peeked = try self.take_();
        }
        return self.peeked;
    }

    fn curr(self: *Lexer) ?u8 {
        return if (self.pos >= self.src.len) null else self.src[self.pos];
    }

    fn adv(self: *Lexer) void {
        self.pos += 1;
    }

    fn skipWhitespace(self: *Lexer) bool {
        var did_skip = false;
        while (self.curr()) |c| {
            if (!ascii.isWhitespace(c)) break;
            self.adv();
            did_skip = true;
        }
        return did_skip;
    }

    fn skipComments(self: *Lexer) bool {
        if (self.curr()) |c| {
            if (c != '#') return false;
            self.adv();
            while (self.curr()) |c_| {
                if (c_ == '\n') {
                    self.adv();
                    break;
                }
                self.adv();
            }
            return true;
        } else return false;
    }

    fn operator(self: *Lexer) ?Token {
        const tag: Tag = switch (self.curr().?) {
            '=' => return self.multiCharOperator(.@"=", .@"=>", '>'),
            '+' => return self.multiCharOperator(.@"+", .@"++", '+'),
            '-' => return self.minus(),
            '*' => .@"*",
            '/' => .@"/",
            '%' => .@"%",
            '(' => return self.multiCharOperator(.@"(", .@"()", ')'),
            ')' => .@")",
            '[' => .@"[",
            ']' => .@"]",
            '{' => .@"{",
            '}' => .@"}",
            ';' => .@";",
            ',' => .@",",
            ':' => return self.multiCharOperator(.@":", .@"::", ':'),
            '.' => self.dot(),
            '<' => return self.multiCharOperator(.@"<", .@"<=", '='),
            '>' => return self.multiCharOperator(.@">", .@">=", '='),
            '!' => return self.multiCharOperator(.@"!", .@"!=", '='),
            '$' => .@"$",
            '_' => ._,
            '|' => .@"|",
            else => return null,
        };

        const tok = Token{ .tag = tag, .where = self.src[self.pos .. self.pos + 1] };
        self.adv();
        return tok;
    }

    fn minus(self: *Lexer) Token {
        const begin = self.pos;
        self.adv();
        var tag: Tag = undefined;
        if (self.curr()) |c| {
            switch (c) {
                ' ' => tag = .@"-",
                '>' => {
                    self.adv();
                    tag = .@"->";
                },
                else => tag = .neg,
            }
        } else tag = .@"-";
        return .{ .tag = tag, .where = self.src[begin..self.pos] };
    }

    fn dot(self: *Lexer) Token.Tag {
        if (self.pos > 0 and ascii.isWhitespace(self.src[self.pos - 1])) {
            return .@" .";
        } else return .@".";
    }

    fn multiCharOperator(self: *Lexer, single_tag: Tag, multi_tag: Tag, second_char: u8) ?Token {
        const begin = self.pos;
        self.adv();
        var tag: Tag = undefined;
        if (self.curr() != null and self.curr().? == second_char) {
            self.adv();
            tag = multi_tag;
        } else tag = single_tag;
        const where = self.src[begin..self.pos];
        return .{ .tag = tag, .where = where };
    }

    fn isIdentCharContinue(c: u8) bool {
        return ascii.isAlphabetic(c) or ascii.isDigit(c) or c == '_' or c == '\'';
    }

    fn identOrKw(self: *Lexer) ?Token {
        if (ascii.isAlphabetic(self.curr().?)) {
            const begin = self.pos;

            while (self.curr()) |c| {
                if (!isIdentCharContinue(c)) break;
                self.adv();
            }

            const where = self.src[begin..self.pos];

            var tag: Tag = .ident;
            inline for (kws) |kw| {
                if (mem.eql(u8, where, @tagName(kw))) {
                    tag = kw;
                    break;
                }
            }

            return .{ .tag = tag, .where = where };
        } else return null;
    }

    fn infix(self: *Lexer) !?Token {
        if (self.curr().? != '\'') return null;
        self.adv();

        if (self.curr() != null and ascii.isAlphabetic(self.curr().?)) {
            const begin = self.pos;

            while (self.curr()) |c| {
                if (!isIdentCharContinue(c)) break;
                self.adv();
            }

            const where = self.src[begin..self.pos];
            return .{ .tag = .infix, .where = where };
        } else {
            const where = self.src[self.pos - 1 .. self.pos];
            try self.diagnostics.addDiagnostic(.{
                .description = .{ .static = "empty infix operator" },
                .location = where,
            });
            return error.LexicalError;
        }
    }

    fn string(self: *Lexer) !?Token {
        if (self.curr().? != '\"') return null;

        self.adv();
        const begin = self.pos;

        while (self.curr() != null and self.curr().? != '\n') {
            if (self.curr() == '\"') {
                const where = self.src[begin..self.pos];
                self.adv();
                return .{ .tag = .string, .where = where };
            }
            self.adv();
        }
        const where = self.src[begin..self.pos];
        try self.diagnostics.addDiagnostic(.{
            .description = .{ .static = "unterminated string" },
            .location = where,
        });
        return error.LexicalError;
    }

    fn number(self: *Lexer) ?Token {
        if (!ascii.isDigit(self.curr().?)) return null;

        var has_dot = false;

        const begin = self.pos;
        while (self.curr()) |c| {
            if (c == '.') {
                has_dot = true;
            } else if (!ascii.isDigit(c)) break;
            self.adv();
        }

        const where = self.src[begin..self.pos];
        const tag: Tag = if (has_dot) .float else .int;
        return .{ .tag = tag, .where = where };
    }
};

test Lexer {
    const testing = std.testing;
    const src = @embedFile("test-inputs/fib.blue");

    var diagnostics = DiagnosticList.init(testing.allocator, src);
    defer diagnostics.deinit();

    var lx = Lexer.init(src, &diagnostics);

    var tags = ArrayList(Tag).init(testing.allocator);
    defer tags.deinit();

    while (try lx.take()) |t| try tags.append(t.tag);

    const expected_tags: []const Tag = &.{
        .let,
        .ident,
        .ident,
        .@"=",
        .@"if",
        .ident,
        .@"<",
        .int,
        .then,
        .ident,
        .@"else",
        .ident,
        .@"(",
        .ident,
        .@"-",
        .int,
        .@")",
        .@"+",
        .ident,
        .@"(",
        .ident,
        .@"-",
        .int,
        .@")",
        .@";",
        .in,
        .ident,
        .int,
    };

    try testing.expectEqualSlices(Tag, expected_tags, tags.items);
}
