//!
//! The lexer module that is responsible for turning a given text into a list of tokens.
//!
const std = @import("std");
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

// The different modes that can currently be parsing
const Parsing_Type = enum { NONE, IDENTIFIER, SYMBOL };

/// Tokenizes a given text into a list of tokens.
pub fn tokenize(self: *Self, text: []const u8) !void {
    // This function is very naive and poorly optimized :)
    // But it get's the job done 🤩

    // The current line and column
    var line: u32 = 1;
    var column: u32 = 1;

    // The current parsing type and current token we are parsing
    var parsing_type = Parsing_Type.NONE;
    var current_token: ?Token = null;
    var content = ArrayList(u8).init(self.allocator);
    defer content.deinit();

    for (text) |elem| {
        // If we encounter a whitespace character
        if (is_whitespace(elem)) {
            if (elem == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }

            // Add the current token we're parsing
            if (current_token) |*token| {
                try self.add_token(token, &content, parsing_type);
                current_token = null;
                parsing_type = Parsing_Type.NONE;
            }

            continue;
        }

        // If we encounter an alphabetic character, start parsing an identifier
        if (is_alphabetic(elem) and parsing_type != Parsing_Type.IDENTIFIER) {
            if (current_token) |*token| {
                try self.add_token(token, &content, parsing_type);
            }

            parsing_type = Parsing_Type.IDENTIFIER;
            current_token = Token{ .kind = Node_Symbol.IDENTIFIER, .content = try self.allocator.alloc(u8, 0), .cl_start = column, .cl_end = 0, .ln_start = line, .ln_end = 0 };
        }

        if (is_symbol(elem) and parsing_type != Parsing_Type.SYMBOL) {
            if (current_token) |*token| {
                try self.add_token(token, &content, parsing_type);
            }

            parsing_type = Parsing_Type.SYMBOL;
            // We set IDENTIFIER here, but it will be overwritten later
            current_token = Token{ .kind = Node_Symbol.IDENTIFIER, .content = try self.allocator.alloc(u8, 0), .cl_start = column, .cl_end = 0, .ln_start = line, .ln_end = 0 };
        }

        if (current_token != null) {
            try content.append(elem);
            current_token.?.ln_end = line;
            current_token.?.cl_end = column;
        }

        if (current_token) |*token| {
            // This code here might be a little confusing
            // It's very slow, but gets the job done
            if (parsing_type == Parsing_Type.SYMBOL and !can_be_more_symbols(content.items)) {
                try self.add_token(token, &content, parsing_type);
                current_token = null;
                parsing_type = Parsing_Type.NONE;
            }
        }

        column += 1;
    }

    // If there still is a token we're parsing add it to the list of tokens
    if (current_token) |*token| {
        try self.add_token(token, &content, parsing_type);
    }

    var eot_token = Token{
        .kind = Node_Symbol.END_OF_FILE,
        .content = try self.allocator.alloc(u8, 0),
        // Line number and column doesn't make sense for the EOT token
        .cl_start = 0,
        .cl_end = 0,
        .ln_start = 0,
        .ln_end = 0,
    };

    try self.tokens.append(eot_token);
}

fn add_token(self: *Self, token: *Token, content: *ArrayList(u8), parsing_type: Parsing_Type) !void {
    token.*.content = try self.allocator.dupe(u8, content.items);
    content.*.deinit();
    content.* = ArrayList(u8).init(self.allocator);

    if (parsing_type == Parsing_Type.SYMBOL) {
        var kind = try get_symbol(token.*.content);
        token.*.kind = kind;
    }

    try self.tokens.append(token.*);
}

fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\n' or c == '\t';
}

fn is_alphabetic(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

const symbol_chars = "[]{}()<>+-*/=,:.%;";
const symbols = [_]struct { symbol: []const u8, kind: Node_Symbol }{
    .{ .symbol = ",", .kind = Node_Symbol.COMMA },
    .{ .symbol = ".", .kind = Node_Symbol.COMMA },
    .{ .symbol = ":=", .kind = Node_Symbol.COLON_EQUALS },
    .{ .symbol = "<-", .kind = Node_Symbol.ASSIGN },
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
    for (symbol_chars) |t| {
        if (c == t) {
            return true;
        }
    }
    return false;
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
        if (std.mem.eql(u8, s.symbol[0..c.len], c)) {
            amount += 1;

            if (amount > 1) {
                return true;
            }
        }
    }

    return false;
}

fn is_numeric(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn is_alphanumeric(c: u8) bool {
    return is_alphabetic(c) or is_numeric(c);
}

test "tokenize #1" {
    // TODO: REMOVE
    //
    // const index = 0;
    // std.log.warn("", .{});
    // std.log.warn("kind: {}", .{lxr.tokens.items[index].kind});
    // std.log.warn("content: {s}", .{lxr.tokens.items[index].content});
    // std.log.warn("ln_start: {d}", .{lxr.tokens.items[index].ln_start});
    // std.log.warn("ln_end: {d}", .{lxr.tokens.items[index].ln_end});
    // std.log.warn("cl_start: {d}", .{lxr.tokens.items[index].cl_start});
    // std.log.warn("cl_end: {d}", .{lxr.tokens.items[index].cl_end});

    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example\n foo");

    try std.testing.expect(std.meta.eql(lxr.tokens.items.len, 2));
    try std.testing.expectEqualDeep(lxr.tokens.items[0], Token{ .kind = Node_Symbol.IDENTIFIER, .content = "example", .cl_start = 1, .cl_end = 7, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[1], Token{ .kind = Node_Symbol.IDENTIFIER, .content = "foo", .cl_start = 2, .cl_end = 4, .ln_start = 2, .ln_end = 2 });
}

test "tokenize #2" {
    // TODO: REMOVE
    //
    // const index = 0;
    // std.log.warn("", .{});
    // std.log.warn("kind: {}", .{lxr.tokens.items[index].kind});
    // std.log.warn("content: {s}", .{lxr.tokens.items[index].content});
    // std.log.warn("ln_start: {d}", .{lxr.tokens.items[index].ln_start});
    // std.log.warn("ln_end: {d}", .{lxr.tokens.items[index].ln_end});
    // std.log.warn("cl_start: {d}", .{lxr.tokens.items[index].cl_start});
    // std.log.warn("cl_end: {d}", .{lxr.tokens.items[index].cl_end});

    var lxr = Self.init(std.heap.page_allocator);
    defer lxr.deinit();

    try lxr.tokenize("example foo<-baz()<-");

    try std.testing.expect(std.meta.eql(lxr.tokens.items.len, 2));
    try std.testing.expectEqualDeep(lxr.tokens.items[0], Token{ .kind = Node_Symbol.IDENTIFIER, .content = "example", .cl_start = 1, .cl_end = 7, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[1], Token{ .kind = Node_Symbol.IDENTIFIER, .content = "foo", .cl_start = 9, .cl_end = 11, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[2], Token{ .kind = Node_Symbol.ASSIGN, .content = "<-", .cl_start = 12, .cl_end = 13, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[5], Token{ .kind = Node_Symbol.IDENTIFIER, .content = "baz", .cl_start = 14, .cl_end = 16, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[3], Token{ .kind = Node_Symbol.OPEN_PARENTHESIS, .content = "(", .cl_start = 17, .cl_end = 17, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[4], Token{ .kind = Node_Symbol.CLOSED_PARENTHESIS, .content = ")", .cl_start = 18, .cl_end = 18, .ln_start = 1, .ln_end = 1 });
    try std.testing.expectEqualDeep(lxr.tokens.items[4], Token{ .kind = Node_Symbol.ASSIGN, .content = "<-", .cl_start = 19, .cl_end = 20, .ln_start = 1, .ln_end = 1 });
}
