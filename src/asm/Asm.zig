//!
//! The intermediate language assembler
//!
const Self = @This();
const std = @import("std");
const Token = @import("Token.zig");
const Error = @import("Error.zig");
const int = @import("arch").int;
const instr = @import("arch").instr;
const AddressPatcher = @import("AddressPatcher.zig");

code: std.ArrayList(u8),
scanner: Token.Scanner,
errors: *std.ArrayList(Error),
fn_patcher: AddressPatcher,
lbl_patcher: AddressPatcher,
entry: ?u64,

pub fn init(source: []const u8, errors: *std.ArrayList(Error), allocator: std.mem.Allocator) Self {
    var self: Self = .{
        .code = std.ArrayList(u8).init(allocator),
        .scanner = .{ .source = source, .errors = errors },
        .errors = errors,
        .fn_patcher = AddressPatcher.init(allocator),
        .lbl_patcher = AddressPatcher.init(allocator),
        .entry = null,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.code.deinit();
    self.fn_patcher.deinit();
    self.lbl_patcher.deinit();
}

pub fn parse(self: *Self) !void {
    while (try self.scanner.peek()) |_| {
        try self.function();
    }

    var unres = self.fn_patcher.unresolvedIterator();
    var had_unres = false;
    while (unres.next()) |fname| {
        try self.errors.append(.{
            .tag = .unresolved_function,
            .where = fname,
        });
        had_unres = true;
    }

    if (had_unres) {
        return error.UnresolvedFunction;
    }

    if (self.entry == null) {
        try self.errors.append(.{
            .tag = .no_main,
            .where = null,
            .extra = "no 'main' function",
        });
        return error.NoMain;
    }
}

pub fn emit(self: *Self, writer: anytype) !void {
    // TODO: header
    try writer.writeAll(self.code.items);
}

fn function(self: *Self) !void {
    _ = try self.expectKeyword(.function);

    const name = try self.expectTag(.string);

    _ = try self.expectKeyword(.params);
    const num_params = (try self.expectTag(.immed)).tag.immed;

    _ = try self.expectKeyword(.locals);
    const num_locals = (try self.expectTag(.immed)).tag.immed;

    _ = try self.expectKeyword(.begin);
    try self.initFunction(name, num_params, num_locals);

    while (try self.scanner.peek()) |token| switch (token.tag) {
        .keyword => |kw| switch (kw) {
            .end => break,
            else => {
                try self.errors.append(.{
                    .tag = .unexpected_token,
                    .where = token.where,
                    .extra = "unexpected keyword in function body",
                });
                return error.UnexpectedToken;
            },
        },
        else => {
            try self.statement();
        },
    };
    _ = try self.expectKeyword(.end);
    try self.endFunction();
}

fn statement(self: *Self) !void {
    const token = try self.expectSomething();
    switch (token.tag) {
        .instr => |i| {
            // write instruction
            try self.code.append(@intFromEnum(i));
            // write operand
            if (i.hasOperand()) {
                switch (i) {
                    .call => {
                        const fname = (try self.expectTag(.string)).where;
                        const patch = self.code.items.len;
                        _ = try self.code.addManyAsArray(8);
                        try self.fn_patcher.patch(fname, patch, self.code.items);
                    },
                    .jmp, .jmpnz => {
                        const lname = (try self.expectTag(.label)).where;
                        const patch = self.code.items.len;
                        _ = try self.code.addManyAsArray(8);
                        try self.lbl_patcher.patch(lname, patch, self.code.items);
                    },
                    else => {
                        const immed = (try self.expectTag(.immed)).tag.immed;
                        try int.encodeILEB128(self.code.writer(), immed);
                    },
                }
            }
        },
        .label => {
            const lname = token.where;
            self.lbl_patcher.resolve(lname, self.code.items.len, self.code.items) catch |e| {
                if (e == error.AlreadyResolved) {
                    try self.errors.append(.{
                        .tag = .duplicate_label,
                        .where = lname,
                    });
                    return error.DuplicateLabel;
                }
            };
        },
        else => {
            try self.errors.append(.{
                .tag = .unexpected_token,
                .where = token.where,
                .extra = "expected instruction or label",
            });
            return error.UnexpectedToken;
        },
    }
}

fn expectSomething(self: *Self) !Token {
    const token = try self.scanner.next();
    if (token == null) {
        try self.errors.append(.{
            .tag = .unexpected_eof,
            .where = self.scanner.source[self.scanner.source.len - 1 ..],
        });
        return error.UnexpectedEOF;
    }
    return token.?;
}

fn expectTag(self: *Self, comptime expected: std.meta.Tag(Token.Tag)) !Token {
    const token = try self.expectSomething();
    if (token.tag != expected) {
        try self.errors.append(.{
            .tag = .unexpected_token,
            .where = token.where,
            .extra = "expected `" ++ @tagName(expected) ++ "` token",
        });
        return error.UnexpectedToken;
    }
    return token;
}

fn expectKeyword(self: *Self, comptime expected: Token.Keyword) !Token {
    const token = try self.expectSomething();
    if (token.tag != .keyword or token.tag.keyword != expected) {
        try self.errors.append(.{
            .tag = .unexpected_token,
            .where = token.where,
            .extra = "expected `" ++ @tagName(expected) ++ "` keyword",
        });
        return error.UnexpectedToken;
    }
    return token;
}

fn initFunction(self: *Self, name: Token, num_params: i64, num_locals: i64) !void {
    const address = self.code.items.len;
    self.fn_patcher.resolve(name.where, address, self.code.items) catch |e| {
        if (e == error.AlreadyResolved) {
            try self.errors.append(.{
                .tag = .duplicate_function,
                .where = name.where,
            });
            return error.DuplicateFunction;
        }
    };
    if (std.mem.eql(u8, name.where, instr.entry_name)) {
        self.entry = address;
    }
    _ = .{ num_params, num_locals }; // TODO
}

fn endFunction(self: *Self) !void {
    var unres = self.lbl_patcher.unresolvedIterator();
    var had_unres = false;
    while (unres.next()) |lbl| {
        try self.errors.append(.{
            .tag = .unresolved_label,
            .where = lbl,
        });
        had_unres = true;
    }

    self.lbl_patcher.reset();

    if (had_unres) {
        return error.UnresolvedLabel;
    }
}

const ErrorTag = @TypeOf(@as(Error, undefined).tag);

test "parsing" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\    push %10
        \\    call "Fibonacci"
        \\    ret
        \\-end
        \\
        \\-function "Fibonacci"
        \\-params %1
        \\-locals %0
        \\-begin
        \\    load %0
        \\    push %2
        \\    cmp_lt
        \\    jmpnz .rec
        \\    load %0
        \\    ret
        \\.rec
        \\    load %0
        \\    push %1
        \\    sub
        \\    call "Fibonacci"
        \\    load %0
        \\    push %2
        \\    sub
        \\    call "Fibonacci"
        \\    add
        \\    ret
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectEqual(void{}, assembler.parse());
    try std.testing.expect(errors.items.len == 0);
}

test "unresolved label" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\jmp .label
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.UnresolvedLabel, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.unresolved_label, errors.items[0].tag);
    try std.testing.expectEqualStrings(errors.items[0].where.?, "label");
}

test "unresolved function" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\call "func"
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.UnresolvedFunction, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.unresolved_function, errors.items[0].tag);
    try std.testing.expectEqualStrings("func", errors.items[0].where.?);
}

test "no main" {
    const source =
        \\
        \\-function "func"
        \\-params %0
        \\-locals %0
        \\-begin
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.NoMain, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.no_main, errors.items[0].tag);
}

test "duplicate label" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\.label
        \\.label
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.DuplicateLabel, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.duplicate_label, errors.items[0].tag);
    try std.testing.expectEqualStrings("label", errors.items[0].where.?);
}

test "duplicate function" {
    const source =
        \\
        \\-function "func"
        \\-params %0
        \\-locals %0
        \\-begin
        \\-end
        \\
        \\-function "func"
        \\-params %0
        \\-locals %0
        \\-begin
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.DuplicateFunction, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.duplicate_function, errors.items[0].tag);
    try std.testing.expectEqualStrings("func", errors.items[0].where.?);
}

test "unexpected token" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\-function
        \\-end
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.UnexpectedToken, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.unexpected_token, errors.items[0].tag);
    try std.testing.expectEqualStrings("function", errors.items[0].where.?);
}

test "unexpected eof" {
    const source =
        \\
        \\-function "main"
        \\-params %0
        \\-locals %0
        \\-begin
        \\
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var assembler = Self.init(source, &errors, std.testing.allocator);
    defer assembler.deinit();

    try std.testing.expectError(error.UnexpectedEOF, assembler.parse());
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(ErrorTag.unexpected_eof, errors.items[0].tag);
}
