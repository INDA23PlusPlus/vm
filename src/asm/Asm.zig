//!
//! The intermediate language assembler
//!
const Self = @This();
const std = @import("std");
const Token = @import("Token.zig");
const Error = @import("Error.zig");
const int = @import("arch").int;
const AddressPatcher = @import("AddressPatcher.zig");

code: std.ArrayList(u8),
scanner: Token.Scanner,
errors: *std.ArrayList(Error),
fn_patcher: AddressPatcher,
lbl_patcher: AddressPatcher,

pub fn init(source: []const u8, errors: *std.ArrayList(Error), allocator: std.mem.Allocator) Self {
    var self: Self = .{
        .code = std.ArrayList(u8).init(allocator),
        .scanner = .{ .source = source, .errors = errors },
        .errors = errors,
        .fn_patcher = AddressPatcher.init(allocator),
        .lbl_patcher = AddressPatcher.init(allocator),
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
    while (unres.next()) |fname| {
        try self.errors.append(.{
            .tag = .unresolved_function,
            .where = fname,
        });
    }
}

fn function(self: *Self) !void {
    _ = try self.expectKeyword(.function);

    const name = try self.expectTag(.string);

    _ = try self.expectKeyword(.params);
    const num_params = (try self.expectTag(.{ .immed = undefined })).tag.immed;

    _ = try self.expectKeyword(.locals);
    const num_locals = (try self.expectTag(.{ .immed = undefined })).tag.immed;

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
                return error.ParseError;
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
                        const immed = (try self.expectTag(.{ .immed = undefined })).tag.immed;
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
                    return e;
                }
            };
        },
        else => {
            try self.errors.append(.{
                .tag = .unexpected_token,
                .where = token.where,
                .extra = "expected instruction or label",
            });
            return error.ParseError;
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
        return error.ParseError;
    }
    return token.?;
}

fn expectTag(self: *Self, comptime expected: Token.Tag) !Token {
    const token = try self.expectSomething();
    if (@intFromEnum(token.tag) != @intFromEnum(expected)) {
        try self.errors.append(.{
            .tag = .unexpected_token,
            .where = token.where,
            .extra = "expected `" ++ @tagName(expected) ++ "` token",
        });
        return error.ParseError;
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
        return error.ParseError;
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
            return e;
        }
    };
    _ = .{ num_params, num_locals }; // TODO
}

fn endFunction(self: *Self) !void {
    var unres = self.lbl_patcher.unresolvedIterator();
    while (unres.next()) |lbl| {
        try self.errors.append(.{
            .tag = .unresolved_label,
            .where = lbl,
        });
    }
    self.lbl_patcher.reset();
}
