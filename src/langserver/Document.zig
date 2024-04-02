//!
//! Stores text document and corresponding compiler data.
//!

const std = @import("std");
const Document = @This();
const lsp = @import("lsp.zig");

// `uri` is managed by DocumentStore as it's used as key to this document
uri: []const u8,
// The rest of the fields are managed here
version: i32,
text: []const u8,
diagnostics: std.ArrayList(lsp.Diagnostic),

pub fn init(
    alloc: std.mem.Allocator,
    uri: []const u8,
    version: i32,
    text: []const u8,
) !Document {
    return .{
        .uri = uri,
        .version = version,
        .text = try alloc.dupe(u8, text),
        .diagnostics = std.ArrayList(lsp.Diagnostic).init(alloc),
    };
}

pub fn deinit(self: *Document, alloc: std.mem.Allocator) void {
    alloc.free(self.text);
    self.diagnostics.deinit();
}
