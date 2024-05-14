//!
//! VeMod Assembly diagnostics.
//!
const Document = @import("../Document.zig");
const asm_ = @import("asm");
const std = @import("std");
const json_rpc = @import("../json_rpc.zig");
const lsp = @import("../lsp.zig");
const vemod_diagnostic = @import("diagnostic");
const DiagnosticList = vemod_diagnostic.DiagnosticList;
const SourceRef = vemod_diagnostic.SourceRef;

fn lspRangeFromSourceLocation(source: []const u8, where: []const u8) !lsp.Range {
    const ref = try SourceRef.init(source, where);
    const line = @as(i32, @intCast(ref.line_num - 1));
    const character = @as(i32, @intCast(ref.offset));
    const length = @as(i32, @intCast(ref.string.len));
    return .{
        .start = .{ .line = line, .character = character },
        .end = .{ .line = line, .character = character + length },
    };
}

fn lspSeverityFromVemodSeverity(severity: vemod_diagnostic.Diagnostic.Severity) lsp.DiagnosticSeverity {
    return switch (severity) {
        .Hint => .Hint,
        .Error => .Error,
        .Warning => .Warning,
    };
}

/// Produce diagnostics for assembly source.
pub fn produceDiagnostics(doc: *Document, alloc: std.mem.Allocator) !void {
    std.log.info("Producing diagnostics for document {s}", .{doc.uri});

    var diagnostics = DiagnosticList.init(alloc, doc.text);
    defer diagnostics.deinit();

    var asm_instance = asm_.Asm.init(doc.text, alloc, &diagnostics);
    defer asm_instance.deinit();

    var msg_buf = std.ArrayList(u8).init(alloc);
    defer msg_buf.deinit();

    try asm_instance.assemble();

    std.log.info(
        "{d} diagnostics found (excluding related information)",
        .{diagnostics.list.items.len},
    );

    var it = diagnostics.iterator();
    while (it.next()) |diagnostic| {
        if (diagnostic.location == null) {
            // How do we publish diagnostics without locations ?
            continue;
        }

        msg_buf.clearRetainingCapacity();
        try msg_buf.writer().print(
            "{s}: {s}.",
            .{
                @tagName(diagnostic.severity),
                diagnostics.getDescriptionString(diagnostic.description),
            },
        );

        const range = try lspRangeFromSourceLocation(doc.text, diagnostic.location.?);
        const severity = lspSeverityFromVemodSeverity(diagnostic.severity);

        try doc.diagnostics.append(.{
            .range = range,
            .severity = @intFromEnum(severity),
            .message = try alloc.dupe(u8, msg_buf.items),
            .relatedInformation = null,
        });
    }
}
