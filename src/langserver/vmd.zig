//!
//! VeMod Assembly diagnostics.
//!
const Document = @import("Document.zig");
const asm_ = @import("asm");
const std = @import("std");
const json_rpc = @import("json_rpc.zig");
const lsp = @import("lsp.zig");

/// Produce diagnostics for assembly source.
pub fn produceDiagnostics(doc: *Document, alloc: std.mem.Allocator) !void {
    std.log.info("Producing diagnostics for document {s}", .{doc.uri});

    var errors = std.ArrayList(asm_.Error).init(alloc);
    defer errors.deinit();

    var asm_instance = asm_.Asm.init(doc.text, alloc, &errors);
    defer asm_instance.deinit();

    var msg_buf = std.ArrayList(u8).init(alloc);

    try asm_instance.assemble();

    std.log.info("{d} errors found", .{errors.items.len});

    for (errors.items) |err| {
        if (err.where == null) {
            // How do we publish diagnostics without locations ?
            continue;
        }

        msg_buf.clearRetainingCapacity();
        _ = try msg_buf.writer().write(@tagName(err.tag));
        if (err.extra) |extra| {
            _ = try msg_buf.writer().print(": {s}", .{extra});
        }

        _ = try msg_buf.writer().print(" \"{s}\"", .{err.where.?});

        // Compute location
        const ref = try asm_.SourceRef.init(doc.text, err.where.?);
        const line = @as(i32, @intCast(ref.line_num - 1));
        const character = @as(i32, @intCast(ref.offset));
        const length = @as(i32, @intCast(ref.string.len));

        const range = lsp.Range{
            .start = .{ .line = line, .character = character },
            .end = .{ .line = line, .character = character + length },
        };

        try doc.diagnostics.append(.{
            .range = range,
            .severity = @intFromEnum(lsp.DiagnosticSeverity.Error),
            .message = try alloc.dupe(u8, msg_buf.items),
        });
    }
}