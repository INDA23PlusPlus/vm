const std = @import("std");
const Instruction = @import("arch").Instruction;
const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

const Patcher = @This();

const Ref = struct {
    symbol: []const u8,
    offset: usize,
};

decls: std.StringHashMap(usize),
refs: std.ArrayList(Ref),
diagnostics: *DiagnosticList,

pub fn init(
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticList,
) Patcher {
    return .{
        .decls = std.StringHashMap(usize).init(allocator),
        .refs = std.ArrayList(Ref).init(allocator),
        .diagnostics = diagnostics,
    };
}

pub fn deinit(self: *Patcher) void {
    self.decls.deinit();
    self.refs.deinit();
}

pub fn decl(self: *Patcher, symbol: []const u8, offset: usize) !void {
    if (self.decls.getEntry(symbol)) |entry| {
        try self.diagnostics.addDiagnostic(.{
            .description = .{
                .dynamic = try self.diagnostics.newDynamicDescription(
                    "duplicate symbol \"{s}\"",
                    .{symbol},
                ),
            },
            .location = symbol,
        });
        try self.diagnostics.addRelated(.{
            .description = .{ .static = "previously defined here" },
            .severity = .Hint,
            .location = entry.key_ptr.*,
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
            try self.diagnostics.addDiagnostic(.{
                .description = .{
                    .dynamic = try self.diagnostics.newDynamicDescription(
                        "unresolved symbol \"{s}\"",
                        .{ref.symbol},
                    ),
                },
                .location = ref.symbol,
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
