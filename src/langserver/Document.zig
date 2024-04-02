//!
//! Stores text document and corresponding compiler data.
//!

const std = @import("std");
const Document = @This();

// `uri` is managed by DocumentStore as it's used as key to this document
uri: []const u8,
// The rest of the fields are managed here
version: i32,
text: []const u8,
// ... add AST etc. here

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
    };
}

pub fn deinit(self: *Document, alloc: std.mem.Allocator) void {
    alloc.free(self.text);
    // TODO: free compiler data
}
