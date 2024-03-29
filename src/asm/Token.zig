const std = @import("std");
const Token = @This();
const instr = @import("arch").instr;
const Error = @import("Error.zig");

tag: Tag,
where: []const u8,

pub const Tag = union(enum) {
    keyword: Keyword,
    string,
    label,
    int: i64,
    float: f64,
    instr: instr.Instruction,
    err,
};

pub const Keyword = enum {
    function,
    begin,
    end,
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
            instr.prefix.keyword => return self.keyword(),
            instr.prefix.integer => return self.integer(),
            instr.prefix.float => return self.float(),
            instr.prefix.label => return self.label(),
            '"' => return self.string(),
            'a'...'z', 'A'...'Z' => return self.instruction(),
            else => {
                const where = self.source[self.cursor .. self.cursor + 1];
                self.advance();
                try self.errors.append(.{ .tag = .invalid_character, .where = where });
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
            if (std.ascii.isWhitespace(c)) {
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
            try self.errors.append(.{ .tag = .invalid_keyword, .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .keyword = kw }, .where = where };
    }

    fn instruction(self: *Scanner) !?Token {
        const where = self.readWord();
        const _instr = std.meta.stringToEnum(instr.Instruction, where) orelse {
            try self.errors.append(.{ .tag = .invalid_instruction, .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .instr = _instr }, .where = where };
    }

    fn integer(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        const int = std.fmt.parseInt(i64, where, 10) catch {
            try self.errors.append(.{ .tag = .invalid_literal, .where = where });
            return .{ .tag = .err, .where = where };
        };
        return Token{ .tag = .{ .int = int }, .where = where };
    }

    fn float(self: *Scanner) !?Token {
        self.advance();
        const where = self.readWord();
        const float_ = std.fmt.parseFloat(f64, where) catch {
            try self.errors.append(.{ .tag = .invalid_literal, .where = where });
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
                    .tag = .unterminated_string,
                    .where = where,
                });
                return .{ .tag = .err, .where = self.readWord() };
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
                .tag = .unterminated_string,
                .where = where,
            });
            return .{ .tag = .err, .where = self.readWord() };
        }
        return Token{ .tag = .string, .where = self.source[begin..end] };
    }
};
