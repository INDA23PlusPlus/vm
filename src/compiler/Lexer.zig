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

const Parsing_Type = enum { NONE, IDENTIFIER, SYMBOL };

pub fn tokenize(self: *Self, text: []const u8) !void {
    // The current line and column
    var ln: u32 = 1;
    var cl: u32 = 1;

    var ln_start: u32 = 1;
    var cl_start: u32 = 1;

    var parsing_type: Parsing_Type = Parsing_Type.NONE;

    var content: []u8 = try self.allocator.alloc(u8, 1024);
    var content_index: u32 = 0;
    defer self.allocator.free(content);

    for (0..text.len) |i| {
        var char = text[i];

        if (is_whitespace(char)) {
            if (parsing_type != Parsing_Type.NONE) {
                var token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
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
                var token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content_index = 0;
            }

            ln_start = ln;
            cl_start = cl;
            parsing_type = Parsing_Type.IDENTIFIER;
        }

        if (is_symbol(char)) {
            if (parsing_type != Parsing_Type.SYMBOL) {
                if (parsing_type != Parsing_Type.NONE) {
                    var token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
                    try self.tokens.append(token);
                    content_index = 0;
                }

                ln_start = ln;
                cl_start = cl;
                parsing_type = Parsing_Type.SYMBOL;
            } else {
                if (!can_be_more_symbols(content[0..content_index])) {
                    var token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
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
        }

        if (parsing_type == Parsing_Type.SYMBOL) {
            if (get_symbol(content[0..content_index]) == error.UnknownSymbol and content_index > 1) {
                var token = try parse_token(self.allocator, content[0..(content_index - 1)], parsing_type, ln_start, ln, cl_start, cl - 1);
                try self.tokens.append(token);
                content[0] = char;
                content_index = 1;

                cl_start = cl;
                ln_start = ln;
            }
        }

        cl += 1;
    }

    if (parsing_type != Parsing_Type.NONE) {
        var token = try parse_token(self.allocator, content[0..content_index], parsing_type, ln_start, ln, cl_start, cl - 1);
        try self.tokens.append(token);
    }
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
    var cloned_content: []u8 = try allocator.alloc(u8, content.len);
    @memcpy(cloned_content, content);

    switch (parsing_type) {
        Parsing_Type.IDENTIFIER => {
            return Token{
                .kind = Node_Symbol.IDENTIFIER,
                .content = cloned_content,
                .ln_start = ln_start,
                .ln_end = ln_end,
                .cl_start = cl_start,
                .cl_end = cl_end,
            };
        },
        Parsing_Type.SYMBOL => {
            if (get_symbol(content) == error.UnknownSymbol) {
                std.debug.panic("example: {s}", .{content});
            }

            return Token{
                .kind = try get_symbol(content),
                .content = cloned_content,
                .ln_start = ln_start,
                .ln_end = ln_end,
                .cl_start = cl_start,
                .cl_end = cl_end,
            };
        },
        Parsing_Type.NONE => {
            if (builtin.mode == .Debug) {
                std.debug.panic("Can't parse NONE as token", .{});
            }
        },
    }
}

fn double_content_length(allocator: Allocator, content: []u8) !void {
    var new_content: []u8 = try allocator.alloc(u8, content.len * 2);
    std.mem.copy(new_content, content, content.len);
    allocator.free(content);
    content = new_content;
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

const symbols = [_]struct { symbol: []const u8, kind: Node_Symbol }{
    .{ .symbol = ",", .kind = Node_Symbol.COMMA },
    .{ .symbol = ".", .kind = Node_Symbol.DOT },
    .{ .symbol = ":=", .kind = Node_Symbol.COLON_EQUALS },
    .{ .symbol = ":", .kind = Node_Symbol.COLON },
    .{ .symbol = "<-", .kind = Node_Symbol.ASSIGN },
    .{ .symbol = "=", .kind = Node_Symbol.EQUALS },
    .{ .symbol = "!=", .kind = Node_Symbol.NOT_EQUALS },
    .{ .symbol = "<", .kind = Node_Symbol.LESS_THAN },
    .{ .symbol = ">", .kind = Node_Symbol.GREATER_THAN },
    .{ .symbol = "<=", .kind = Node_Symbol.LESS_THAN_EQUALS },
    .{ .symbol = ">=", .kind = Node_Symbol.GREATER_THAN_EQUALS },
    .{ .symbol = "+", .kind = Node_Symbol.PLUS },
    .{ .symbol = "-", .kind = Node_Symbol.MINUS },
    .{ .symbol = "*", .kind = Node_Symbol.TIMES },
    .{ .symbol = "/", .kind = Node_Symbol.DIVIDE },
    .{ .symbol = ";", .kind = Node_Symbol.SEMICOLON },
    .{ .symbol = ",", .kind = Node_Symbol.COMMA },
    .{ .symbol = "(", .kind = Node_Symbol.OPEN_PARENTHESIS },
    .{ .symbol = ")", .kind = Node_Symbol.CLOSED_PARENTHESIS },
    .{ .symbol = "[", .kind = Node_Symbol.OPEN_SQUARE },
    .{ .symbol = "]", .kind = Node_Symbol.CLOSED_SQUARE },
    .{ .symbol = "{", .kind = Node_Symbol.OPEN_CURLY },
    .{ .symbol = "}", .kind = Node_Symbol.CLOSED_CURLY },
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

test "tokenize symbols with identifiers" {
    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example foo<-baz()<-::=example:< -");

    try std.testing.expectEqual(lxr.tokens.items.len, 13);
    // zig fmt: off
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "example", .cl_start = 1,  .cl_end = 7,  .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[0]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "foo",     .cl_start = 9,  .cl_end = 11, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[1]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.ASSIGN,             .content = "<-",      .cl_start = 12, .cl_end = 13, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[2]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "baz",     .cl_start = 14, .cl_end = 16, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[3]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.OPEN_PARENTHESIS,   .content = "(",       .cl_start = 17, .cl_end = 17, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[4]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.CLOSED_PARENTHESIS, .content = ")",       .cl_start = 18, .cl_end = 18, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[5]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.ASSIGN,             .content = "<-",      .cl_start = 19, .cl_end = 20, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[6]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON,              .content = ":",       .cl_start = 21, .cl_end = 21, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[7]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON_EQUALS,       .content = ":=",      .cl_start = 22, .cl_end = 23, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[8]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.IDENTIFIER,         .content = "example", .cl_start = 24, .cl_end = 30, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[9]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.COLON,              .content = ":",       .cl_start = 31, .cl_end = 31, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[10]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.LESS_THAN,          .content = "<",       .cl_start = 32, .cl_end = 32, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[11]);
    try std.testing.expectEqualDeep(Token{ .kind = Node_Symbol.MINUS,              .content = "-",       .cl_start = 34, .cl_end = 34, .ln_start = 1, .ln_end = 1 }, lxr.tokens.items[12]);
    // zig fmt: on
}
