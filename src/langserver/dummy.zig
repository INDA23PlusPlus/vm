//!
//! Dummy diagnostic for testing.
//!

const std = @import("std");
const lsp = @import("lsp.zig");
const json_rpc = @import("json_rpc.zig");
const Document = @import("Document.zig");
const Server = @import("Server.zig");

pub fn produceDiagnostics(server: *Server, uri: []const u8) !void {
    var doc = server.documents.getDocument(uri).?;

    // This is important! Remember this when doing actual stuff.
    doc.diagnostics.clearRetainingCapacity();

    var line: i32 = 0;
    var column: i32 = 0;

    for (doc.text) |c| {
        if (c == '\n') {
            line += 1;
            column = 0;
            continue;
        }

        if (c == 'L') {
            try doc.diagnostics.append(.{
                .range = .{
                    .start = .{ .line = line, .character = column },
                    .end = .{ .line = line, .character = column + 1 },
                },
                .message = "The character 'L' is forbidden",
                .severity = @intFromEnum(lsp.DiagnosticSeverity.Error),
            });
        }

        column += 1;
    }

    const Notification = json_rpc.ServerNotification(lsp.PublishDiagnosticsParams);
    try server.transport.writeServerNotification(Notification{
        .method = @tagName(.@"textDocument/publishDiagnostics"),
        .params = .{
            .uri = uri,
            .version = doc.version,
            .diagnostics = doc.diagnostics.items,
        },
    });
}
