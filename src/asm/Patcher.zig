const std = @import("std");
const Instruction = @import("arch").Instruction;
const Error = @import("Error.zig");

const Patcher = @This();

const Ref = struct {
    symbol: []const u8,
    offset: usize,
};

decls: std.StringHashMap(usize),
refs: std.ArrayList(Ref),
errors: *std.ArrayList(Error),

pub fn init(
    allocator: std.mem.Allocator,
    errors: *std.ArrayList(Error),
) Patcher {
    return .{
        .decls = std.StringHashMap(usize).init(allocator),
        .refs = std.ArrayList(Ref).init(allocator),
        .errors = errors,
    };
}

pub fn deinit(self: *Patcher) void {
    self.decls.deinit();
    self.refs.deinit();
}

pub fn decl(self: *Patcher, symbol: []const u8, offset: usize) !void {
    if (self.decls.getEntry(symbol)) |entry| {
        try self.errors.append(.{
            .tag = .@"Duplicate symbol",
            .where = symbol,
            .related = entry.key_ptr.*,
            .related_msg = "Previously defined here",
        });
    } else {
        try self.decls.put(symbol, offset);
    }
}

pub fn reference(self: *Patcher, symbol: []const u8, offset: usize) !void {
    try self.refs.append(.{ .symbol = symbol, .offset = offset });
}

pub fn patch(self: *Patcher, code: []Instruction) !void {
    for (self.refs.items) |ref| {
        const offset = self.decls.get(ref.symbol) orelse {
            try self.errors.append(.{
                .tag = .@"Unresolved symbol",
                .where = ref.symbol,
            });
            continue;
        };

        code[ref.offset].operand = .{ .location = offset };
    }
}

pub fn reset(self: *Patcher) void {
    self.decls.clearRetainingCapacity();
    self.refs.clearRetainingCapacity();
}
