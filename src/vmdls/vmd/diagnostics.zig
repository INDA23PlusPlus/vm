//!
//! VeMod Assembly diagnostics.
//!
const Document = @import("../Document.zig");
const asm_ = @import("asm");
const std = @import("std");
const json_rpc = @import("../json_rpc.zig");
const lsp = @import("../lsp.zig");

// ALE doesn't display related information,
// so I'm putting this here for now
const put_related_in_separate_diagnostic = true;

fn lspRangeFromSourceLocation(source: []const u8, where: []const u8) !lsp.Range {
    const ref = try asm_.SourceRef.init(source, where);
    const line = @as(i32, @intCast(ref.line_num - 1));
    const character = @as(i32, @intCast(ref.offset));
    const length = @as(i32, @intCast(ref.string.len));
    return .{
        .start = .{ .line = line, .character = character },
        .end = .{ .line = line, .character = character + length },
    };
}

/// Produce diagnostics for assembly source.
pub fn produceDiagnostics(doc: *Document, alloc: std.mem.Allocator) !void {
    std.log.info("Producing diagnostics for document {s}", .{doc.uri});

    var source = try asm_.preproc.run(doc.text, alloc);
    defer alloc.free(source);

    var errors = std.ArrayList(asm_.Error).init(alloc);
    defer errors.deinit();

    var asm_instance = asm_.Asm.init(source, alloc, &errors);
    defer asm_instance.deinit();

    var msg_buf = std.ArrayList(u8).init(alloc);
    defer msg_buf.deinit();

    try asm_instance.assemble();

    std.log.info("{d} errors found", .{errors.items.len});

    for (errors.items) |err| {
        if (err.where == null) {
            // How do we publish diagnostics without locations ?
            continue;
        }

        msg_buf.clearRetainingCapacity();
        _ = try msg_buf.writer().write(@tagName(err.tag));
        if (err.where.?.len > 0) {
            _ = try msg_buf.writer().print(" \"{s}\"", .{err.where.?});
        }
        if (err.extra) |extra| {
            _ = try msg_buf.writer().print(": {s}", .{extra});
        }

        // Compute location(s)
        const range = try lspRangeFromSourceLocation(source, err.where.?);
        var related: ?[]lsp.DiagnosticRelatedInformation = null;

        if (err.related) |rel| {
            const rel_range = try lspRangeFromSourceLocation(source, rel);

            if (put_related_in_separate_diagnostic) {
                try doc.diagnostics.append(.{
                    .range = rel_range,
                    .severity = @intFromEnum(lsp.DiagnosticSeverity.Hint),
                    .message = try alloc.dupe(u8, err.related_msg.?),
                });
            } else {
                const related_entry = lsp.DiagnosticRelatedInformation{
                    .location = .{
                        .uri = doc.uri,
                        .range = rel_range,
                    },
                    .message = try alloc.dupe(u8, err.related_msg.?),
                };
                related = try alloc.alloc(lsp.DiagnosticRelatedInformation, 1);
                related.?[0] = related_entry;
            }
        }

        try doc.diagnostics.append(.{
            .range = range,
            .severity = @intFromEnum(lsp.DiagnosticSeverity.Error),
            .message = try alloc.dupe(u8, msg_buf.items),
            .relatedInformation = related,
        });
    }
}
