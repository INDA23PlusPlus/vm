//!
//! The lexer module that is responsible for turning a given text into a list of tokens.
//!
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

const Node_Symbol = types.Node_Symbol;
const Token = types.Token;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Self = @This();

allocator: Allocator,
tokens: ArrayList(Token),

pub fn init(allocator: Allocator) Self {
    return .{ .allocator = allocator, .tokens = ArrayList(Token).init(allocator) };
}

pub fn deinit(self: *Self) void {
    for (self.tokens.items) |i| {
        self.allocator.free(i.content);
    }
    self.tokens.deinit();
}

const Parsing_Type = enum { NONE, IDENTIFIER, SYMBOL, NUMBER, STRING };

pub fn tokenize(self: *Self, text: []const u8) !void {
    // The current line and column
    var ln: u32 = 1;
    var cl: u32 = 1;

    var ln_start: u32 = 1;
    var cl_start: u32 = 1;

    var parsing_type: Parsing_Type = Parsing_Type.NONE;

    var is_esc = false;

    var content: []u8 = try self.allocator.alloc(u8, 32);
    var content_index: u32 = 0;
    defer self.allocator.free(content);

    for (text) |char| {
        // NOTE: Just check that we don't go into invalid state
        if (builtin.mode == .Debug) {
            if (is_esc and parsing_type != Parsing_Type.STRING) {
                std.debug.panic("Can't have escape char outside of string", .{});
            }
        }

        if (parsing_type == Parsing_Type.STRING) {
            if (is_esc) {
                is_esc = false;
                content[content_index] = get_esc_symbol(char);
                content_index += 1;
                if (content_index == content.len) {
                    content = try double_size(self.allocator, content);
                }
            } else if (char == '\\') {
                is_esc = true;
            } else if (char == '"') {
                const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl);
                try self.tokens.append(token);
                content_index = 0;
                parsing_type = Parsing_Type.NONE;
            } else {
                content[content_index] = char;
                content_index += 1;
                if (content_index == content.len) {
                    content = try double_size(self.allocator, content);
                }
            }

            if (char == '\n') {
                ln += 1;
                cl = 1;
            } else {
                cl += 1;
            }

            continue;
        }

        if (char == '"') {
            parsing_type = Parsing_Type.STRING;
            ln_start = ln;
            cl_start = cl;
            cl += 1;
            continue;
        }

        if (is_whitespace(char)) {
            if (parsing_type != Parsing_Type.NONE) {
                const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content_index = 0;
                parsing_type = Parsing_Type.NONE;
            }

            if (char == '\n') {
                ln += 1;
                cl = 1;
            } else {
                cl += 1;
            }

            continue;
        }

        if (is_alphabetic(char) and parsing_type != Parsing_Type.IDENTIFIER) {
            if (parsing_type != Parsing_Type.NONE) {
                const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content_index = 0;
            }
            ln_start = ln;
            cl_start = cl;
            parsing_type = Parsing_Type.IDENTIFIER;
        } else if (is_numeric(char) and parsing_type != Parsing_Type.IDENTIFIER and parsing_type != Parsing_Type.NUMBER) {
            if (parsing_type != Parsing_Type.NONE) {
                const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content_index = 0;
            }
            parsing_type = Parsing_Type.NUMBER;
            ln_start = ln;
            cl_start = cl;
        } else if (is_symbol(char) and !(parsing_type == Parsing_Type.NUMBER and char == '.')) {
            if (parsing_type != Parsing_Type.SYMBOL) {
                if (parsing_type != Parsing_Type.NONE) {
                    const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                    try self.tokens.append(token);
                    content_index = 0;
                }
                ln_start = ln;
                cl_start = cl;
                parsing_type = Parsing_Type.SYMBOL;
            } else {
                if (!can_be_more_symbols(content[0..content_index])) {
                    const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                    try self.tokens.append(token);
                    content_index = 0;
                    ln_start = ln;
                    cl_start = cl;
                }
            }
        }

        if (parsing_type != Parsing_Type.NONE) {
            content[content_index] = char;
            content_index += 1;

            if (content_index == content.len) {
                content = try double_size(self.allocator, content);
            }
        }

        if (parsing_type == Parsing_Type.SYMBOL) {
            if (get_symbol(content[0..content_index]) == error.UnknownSymbol and content_index > 1) {
                const token = try parse_token(self.allocator, content[0..(content_index - 1)], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content[0] = char;
                content_index = 1;
                cl_start = cl;
                ln_start = ln;
            }
        }

        cl += 1;
    }

    if (parsing_type == Parsing_Type.STRING) {
        return error.NonTerminatedString;
    }

    if (parsing_type != Parsing_Type.NONE) {
        const token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
        try self.tokens.append(token);
    }
}

fn double_size(allocator: Allocator, content: []u8) ![]u8 {
    var new_content: []u8 = try allocator.alloc(u8, content.len * 2);
    @memcpy(new_content[0..content.len], content);
    allocator.free(content);
    return new_content;
}

fn parse_token(
    allocator: Allocator,
    content: []const u8,
    parsing_type: Parsing_Type,
    ln_start: u32,
    ln_end: u32,
    cl_start: u32,
    cl_end: u32,
) !Token {
    const cloned_content: []u8 = try allocator.alloc(u8, content.len);
    @memcpy(cloned_content, content);

    var kind = Node_Symbol.IDENTIFIER;

    switch (parsing_type) {
        Parsing_Type.IDENTIFIER => {
            for (keywords) |k| {
                if (std.mem.eql(u8, k.word, content)) {
                    kind = k.kind;
                    break;
                }
            }
        },
        Parsing_Type.SYMBOL => {
            kind = try get_symbol(content);
        },
        Parsing_Type.STRING => {
            kind = Node_Symbol.STRING;
        },
        Parsing_Type.NUMBER => {
            kind = try number_node_symbol(cloned_content);
        },
        Parsing_Type.NONE => {
            if (builtin.mode == .Debug) {
                std.debug.panic("Can't parse NONE as token", .{});
            }
        },
    }

    return Token{
        .kind = kind,
        .content = cloned_content,
        .ln_start = ln_start,
        .ln_end = ln_end,
        .cl_start = cl_start,
        .cl_end = cl_end,
    };
}

fn get_esc_symbol(c: u8) u8 {
    switch (c) {
        'n' => return '\n',
        't' => return '\t',
        'r' => return '\r',
        '\\' => return '\\',
        '"' => return '"',
        else => return c,
    }
}

fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\t';
}

fn is_alphabetic(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn is_numeric(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn is_alphanumeric(c: u8) bool {
    return is_alphabetic(c) or is_numeric(c);
}

fn number_node_symbol(c: []const u8) !Node_Symbol {
    var has_dot: bool = false;

    for (c) |char| {
        if (char == '.') {
            if (has_dot) {
                return error.CantHaveMultipleDotsInNumber;
            }

            has_dot = true;
        }
    }

    if (has_dot) {
        return Node_Symbol.FLOAT;
    }

    return Node_Symbol.INT;
}

const keywords = [_]struct { word: []const u8, kind: Node_Symbol }{
    // zig fmt: off
    .{ .word = "def",   .kind = Node_Symbol.DEF },
    .{ .word = "ret",   .kind = Node_Symbol.RET },
    .{ .word = "if",    .kind = Node_Symbol.IF },
    .{ .word = "else",  .kind = Node_Symbol.ELSE },
    .{ .word = "while", .kind = Node_Symbol.WHILE },
    .{ .word = "for",   .kind = Node_Symbol.FOR },
    .{ .word = "chain", .kind = Node_Symbol.CHAIN },
    .{ .word = "break", .kind = Node_Symbol.BREAK },
    // zig fmt: on
};

const symbols = [_]struct { symbol: []const u8, kind: Node_Symbol }{
    // zig fmt: off
    .{ .symbol = ":=", .kind = Node_Symbol.COLON_EQUALS },
    .{ .symbol = ":",  .kind = Node_Symbol.COLON },
    .{ .symbol = ";",  .kind = Node_Symbol.SEMICOLON },
    .{ .symbol = ",",  .kind = Node_Symbol.COMMA },
    .{ .symbol = ".",  .kind = Node_Symbol.DOT },
    .{ .symbol = "{",  .kind = Node_Symbol.OPEN_CURLY },
    .{ .symbol = "}",  .kind = Node_Symbol.CLOSED_CURLY },
    .{ .symbol = "(",  .kind = Node_Symbol.OPEN_PARENTHESIS },
    .{ .symbol = ")",  .kind = Node_Symbol.CLOSED_PARENTHESIS },
    .{ .symbol = "[",  .kind = Node_Symbol.OPEN_SQUARE },
    .{ .symbol = "]",  .kind = Node_Symbol.CLOSED_SQUARE },
    .{ .symbol = "+",  .kind = Node_Symbol.PLUS },
    .{ .symbol = "-",  .kind = Node_Symbol.MINUS },
    .{ .symbol = "*",  .kind = Node_Symbol.TIMES },
    .{ .symbol = "/",  .kind = Node_Symbol.DIVIDE },
    .{ .symbol = "%",  .kind = Node_Symbol.REM },

    .{ .symbol = "&&", .kind = Node_Symbol.AND },
    .{ .symbol = "||", .kind = Node_Symbol.OR },
    .{ .symbol = "!",  .kind = Node_Symbol.NOT },
    .{ .symbol = "=",  .kind = Node_Symbol.EQUALS },
    .{ .symbol = "!=", .kind = Node_Symbol.NOT_EQUALS },
    .{ .symbol = "<",  .kind = Node_Symbol.LESS_THAN },
    .{ .symbol = ">",  .kind = Node_Symbol.GREATER_THAN },
    .{ .symbol = "<=", .kind = Node_Symbol.LESS_THAN_EQUALS },
    .{ .symbol = ">=", .kind = Node_Symbol.GREATER_THAN_EQUALS },
    .{ .symbol = "<<", .kind = Node_Symbol.ASSIGN },
    .{ .symbol = "+<", .kind = Node_Symbol.PLUS_ASSIGN },
    .{ .symbol = "-<", .kind = Node_Symbol.MINUS_ASSIGN },
    .{ .symbol = "*<", .kind = Node_Symbol.TIMES_ASSIGN },
    .{ .symbol = "/<", .kind = Node_Symbol.DIVIDE_ASSIGN },
    // zig fmt: on
};

/// Checks if a char is a symbol char
fn is_symbol(c: u8) bool {
    // Very naive
    return !is_alphanumeric(c) and !is_whitespace(c);
}

/// Gets the symbol kind from a given symbol
/// If the symbol is not found, it returns an error
fn get_symbol(c: []const u8) !Node_Symbol {
    for (symbols) |s| {
        if (std.mem.eql(u8, s.symbol, c)) {
            return s.kind;
        }
    }

    return error.UnknownSymbol;
}

/// Checks if a given symbol is the start of multiple symbols
fn can_be_more_symbols(c: []const u8) bool {
    var amount: i32 = 0;

    for (symbols) |s| {
        if (c.len <= s.symbol.len and std.mem.eql(u8, s.symbol[0..c.len], c)) {
            amount += 1;

            if (s.symbol.len != c.len) {
                return true;
            }
        }
    }

    return false;
}

test "tokenize example code" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("def main() {\n  ret 100;\n}");

    try std.testing.expectEqual(lxr.tokens.items.len, 9);

    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.DEF,                .content = "def",     .cl_start = 1,  .cl_end = 3,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "main",    .cl_start = 5,  .cl_end = 8,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[1]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.OPEN_PARENTHESIS,   .content = "(",       .cl_start = 9,  .cl_end = 9,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[2]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.CLOSED_PARENTHESIS, .content = ")",       .cl_start = 10, .cl_end = 10, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[3]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.OPEN_CURLY,         .content = "{",       .cl_start = 12, .cl_end = 12, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[4]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.RET,                .content = "ret",     .cl_start = 3,  .cl_end = 5,  .ln_start = 2, .ln_end = 2 }, lxr.tokens.items[5]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.INT,                .content = "100",     .cl_start = 7,  .cl_end = 9,  .ln_start = 2, .ln_end = 2 }, lxr.tokens.items[6]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.SEMICOLON,          .content = ";",       .cl_start = 10, .cl_end = 10, .ln_start = 2, .ln_end = 2 }, lxr.tokens.items[7]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.CLOSED_CURLY,       .content = "}",       .cl_start = 1,  .cl_end = 1,  .ln_start = 3, .ln_end = 3 }, lxr.tokens.items[8]);
    // zig fmt: on
}

test "tokenize just identifiers" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example\n foo");

    try std.testing.expectEqual(lxr.tokens.items.len, 2);

    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER, .content = "example", .cl_start = 1, .cl_end = 7, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER, .content = "foo",     .cl_start = 2, .cl_end = 4, .ln_start = 2, .ln_end = 2 }, lxr.tokens.items[1]);
    // zig fmt: on
}

test "tokenize keywords" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example\n for");

    try std.testing.expectEqual(lxr.tokens.items.len, 2);

    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER, .content = "example", .cl_start = 1, .cl_end = 7, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.FOR,        .content = "for",     .cl_start = 2, .cl_end = 4, .ln_start = 2, .ln_end = 2 }, lxr.tokens.items[1]);
    // zig fmt: on
}

test "tokenize symbols with identifiers" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example foo<<baz()<<::=example:< <");

    try std.testing.expectEqual(lxr.tokens.items.len, 13);
    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "example", .cl_start = 1,  .cl_end = 7,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "foo",     .cl_start = 9,  .cl_end = 11, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[1]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.ASSIGN,             .content = "<<",      .cl_start = 12, .cl_end = 13, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[2]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "baz",     .cl_start = 14, .cl_end = 16, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[3]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.OPEN_PARENTHESIS,   .content = "(",       .cl_start = 17, .cl_end = 17, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[4]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.CLOSED_PARENTHESIS, .content = ")",       .cl_start = 18, .cl_end = 18, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[5]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.ASSIGN,             .content = "<<",      .cl_start = 19, .cl_end = 20, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[6]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON,              .content = ":",       .cl_start = 21, .cl_end = 21, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[7]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON_EQUALS,       .content = ":=",      .cl_start = 22, .cl_end = 23, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[8]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "example", .cl_start = 24, .cl_end = 30, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[9]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON,              .content = ":",       .cl_start = 31, .cl_end = 31, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[10]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.LESS_THAN,          .content = "<",       .cl_start = 32, .cl_end = 32, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[11]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.LESS_THAN,          .content = "<",       .cl_start = 34, .cl_end = 34, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[12]);
    // zig fmt: on
}

test "tokenize numbers and identifiers" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("foo100 100 100.0");

    try std.testing.expectEqual(lxr.tokens.items.len, 3);
    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER, .content = "foo100", .cl_start = 1,   .cl_end = 6,   .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.INT,        .content = "100",    .cl_start = 8,   .cl_end = 10,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[1]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.FLOAT,      .content = "100.0",  .cl_start = 12,  .cl_end = 16,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[2]);
    // zig fmt: on
}

test "tokenize invalid numbers with error" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try std.testing.expectError(error.CantHaveMultipleDotsInNumber, lxr.tokenize("100.0.0"));
}

test "tokenize string" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("\"test\"");
    try std.testing.expectEqual(lxr.tokens.items.len, 1);
    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.STRING, .content = "test", .cl_start = 1, .cl_end = 6, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    // zig fmt: on
}

test "tokenize strings with escape" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("\"test be \n 100.0 \\\" \n \"");
    try std.testing.expectEqual(lxr.tokens.items.len, 1);
    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.STRING, .content = "test be \n 100.0 \" \n ", .cl_start = 1, .cl_end = 2, .ln_start = 1, .ln_end = 3 }, lxr.tokens.items[0]);
    // zig fmt: on
}

test "tokenize non terminated string with error" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try std.testing.expectError(error.NonTerminatedString, lxr.tokenize("\"test"));
}

test "tokens can be longer than 32 chars" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("testabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    try std.testing.expectEqual(lxr.tokens.items.len, 1);

    try std.testing.expectEqualDeep(Token{
        .kind = Node_Symbol.IDENTIFIER,
        .content = "testabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
        .cl_start = 1,
        .cl_end = 66,
        .ln_start = 1,
        .ln_end = 1,
    }, lxr.tokens.items[0]);
}
