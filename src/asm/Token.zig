const std = @import("std");
const Opcode = @import("arch").Opcode;
const Token = @This();
const Error = @import("Error.zig");

tag: Tag,
where: []const u8,

pub const Tag = union(enum) {
    keyword: Keyword,
    string,
    identifier,
    label,
    int: i64,
    float: f64,
    instr: Opcode,
    err,
};

pub const Keyword = enum {
    function,
    begin,
    end,
    string,
};

/// The prefix for tokens in the IR
/// E.g. `-function` or `.label`
pub const prefix = struct {
    pub const keyword = '-';
    pub const label = '.';
    pub const integer = '%';
    pub const float = '@';
    pub const identifier = '$';
};

pub const Scanner = struct {
    source: []const u8,
    cursor: usize = 0,
    peeked: ?Token = null,
    errors: *std.ArrayList(Error),

    /// Returns the next token and advances scanner
    pub fn next(self: *Scanner) !?Token {
        if (self.peeked) |peeked| {
            defer self.peeked = null;
            return peeked;
        }

        while (self.skipWhitespace() or self.skipComment()) {}
        if (self.current() == null) return null;
        const c = self.current().?;

        switch (c) {
            prefix.keyword => return self.keyword(),
            prefix.integer => return self.integer(),
            prefix.float => return self.float(),
            prefix.label => return self.label(),
            prefix.identifier => return self.identifier(),
            '"' => return self.string(),
            'a'...'z', 'A'...'Z' => return self.instruction(),
            else => {
                const where = self.source[self.cursor .. self.cursor + 1];
                self.advance();
                try self.errors.append(.{ .tag = .@"Invalid character", .where = where });
                return .{ .tag = .err, .where = where };
            },
        }

        return null;
    }

    /// Returns the next token without advancing
    pub fn peek(self: *Scanner) !?Token {
        if (self.peeked == null) {
            self.peeked = try self.next();
        }
        return self.peeked;
    }

    fn current(self: *const Scanner) ?u8 {
        if (self.cursor >= self.source.len) return null;
        return self.source[self.cursor];
    }

    fn advance(self: *Scanner) void {
        if (self.cursor < self.source.len) self.cursor += 1;
    }

    fn skipWhitespace(self: *Scanner) bool {
        var skip = false;
        while (self.current()) |c| {
            if (c == ' ' or c == '\n') {
                self.advance();
                skip = true;
            } else {
                break;
            }
        }
        return skip;
    }

    fn skipComment(self: *Scanner) bool {
        if (self.current() != null and self.current().? == '#') {
            while (self.current()) |c| {
                if (c == '\n') break;
                self.advance();
            }
            return true;
        }
        return false;
    }

    fn readWord(self: *Scanner) []const u8 {
        const begin = self.cursor;
        while (self.current()) |c| {
            if (std.ascii.isWhitespace(c)) break;
            self.advance();
        }
        return self.source[begin..self.cursor];
    }

    fn keyword(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        const kw = std.meta.stringToEnum(Keyword, where) orelse {
            try self.errors.append(.{ .tag = .@"Invalid keyword", .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .keyword = kw }, .where = where };
    }

    fn identifier(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        return Token{ .tag = .identifier, .where = where };
    }

    fn instruction(self: *Scanner) !?Token {
        const where = self.readWord();
        const _instr = std.meta.stringToEnum(Opcode, where) orelse {
            try self.errors.append(.{ .tag = .@"Invalid instruction", .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .instr = _instr }, .where = where };
    }

    fn integer(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        const int = std.fmt.parseInt(i64, where, 10) catch {
            try self.errors.append(.{ .tag = .@"Invalid literal", .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .int = int }, .where = where };
    }

    fn float(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        const float_ = std.fmt.parseFloat(f64, where) catch {
            try self.errors.append(.{ .tag = .@"Invalid literal", .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .float = float_ }, .where = where };
    }

    fn label(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        return Token{ .tag = .label, .where = where };
    }

    fn string(self: *Scanner) !?Token {
        self.advance();
        const begin = self.cursor;
        var end: usize = undefined;
        while (self.current()) |c| {
            if (c == '\n') {
                const where = self.source[begin..self.cursor];
                try self.errors.append(.{
                    .tag = .@"Unterminated string",
                    .where = where,
                });
                return .{ .tag = .err, .where = self.readWord() };
            }
            if (c == '\\') {
                self.advance();
                self.advance();
                continue;
            }
            if (c == '"') {
                end = self.cursor;
                self.advance();
                break;
            }
            self.advance();
        } else {
            const where = self.source[begin..self.cursor];
            try self.errors.append(.{
                .tag = .@"Unterminated string",
                .where = where,
            });
            return .{ .tag = .err, .where = self.readWord() };
        }
        return Token{ .tag = .string, .where = self.source[begin..end] };
    }
};
