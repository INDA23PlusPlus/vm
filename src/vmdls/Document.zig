//!
//! Stores text document and corresponding compiler data.
//!

const std = @import("std");
const Document = @This();
const lsp = @import("lsp.zig");
const lang = @import("lang.zig");
const vemod = @import("vemod/vemod.zig");
const blue = @import("blue/blue.zig");

// `uri` is managed by DocumentStore as it's used as key to this document
uri: []const u8,
// The rest of the fields are managed here
version: i32,
text: []const u8,
language: ?lang.Tag,
diagnostics: std.ArrayList(lsp.Diagnostic),

pub fn init(
    alloc: std.mem.Allocator,
    uri: []const u8,
    version: i32,
    languageId: []const u8,
    text: []const u8,
) !Document {
    return .{
        .uri = uri,
        .version = version,
        .text = try alloc.dupe(u8, text),
        .language = lang.Tag.map.get(languageId),
        .diagnostics = std.ArrayList(lsp.Diagnostic).init(alloc),
    };
}

pub fn deinit(self: *Document, alloc: std.mem.Allocator) void {
    alloc.free(self.text);
    self.resetDiagnostics(alloc);
    self.diagnostics.deinit();
}

pub fn resetDiagnostics(self: *Document, alloc: std.mem.Allocator) void {
    for (self.diagnostics.items) |diagnostic| {
        alloc.free(diagnostic.message);
        if (diagnostic.relatedInformation) |related| {
            for (related) |rel| {
                alloc.free(rel.message);
            }
            alloc.free(related);
        }
    }
    self.diagnostics.clearRetainingCapacity();
}

pub fn produceDiagnostics(self: *Document, alloc: std.mem.Allocator) !void {
    self.resetDiagnostics(alloc);
    if (self.language) |language| {
        switch (language) {
            .vemod => try vemod.produceDiagnostics(self, alloc),
            .blue => try blue.produceDiagnostics(self, alloc),
            .melancolang => {
                std.log.warn("Can't produce diagnostics for Melancolang yet.", .{});
            },
        }
    } else {
        std.log.err(
            "Tried to produce diagnostics for document with unknown language: {s}",
            .{self.uri},
        );
    }
}
