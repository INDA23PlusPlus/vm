//!
//! Stores open documents. Mainly exists as a wrapper around a std.StringHashMap,
//! that also manages keys, since messages are deallocated after handling. Text
//! content is managed by individual documents.
//!

const std = @import("std");
const Document = @import("Document.zig");

const DocumentStore = @This();

alloc: std.mem.Allocator,
docs: std.StringHashMap(Document),

pub fn init(allocator: std.mem.Allocator) DocumentStore {
    return .{
        .alloc = allocator,
        .docs = std.StringHashMap(Document).init(allocator),
    };
}

pub fn deinit(self: *DocumentStore) void {
    var it = self.docs.iterator();
    while (it.next()) |kv| {
        self.alloc.free(kv.key_ptr.*);
        kv.value_ptr.deinit(self.alloc);
    }
    self.docs.deinit();
}

pub fn addDocument(
    self: *DocumentStore,
    uri: []const u8,
    version: i32,
    languageId: []const u8,
    text: []const u8,
) !void {
    std.log.info("Add document {s} (version = {d})", .{ uri, version });

    const key = try self.alloc.dupe(u8, uri);
    errdefer self.alloc.free(key);

    var doc = try Document.init(self.alloc, key, version, languageId, text);
    errdefer doc.deinit(self.alloc);

    try self.docs.put(key, doc);
}

pub fn hasDocument(self: *DocumentStore, uri: []const u8) bool {
    return self.docs.contains(uri);
}

pub fn updateDocument(
    self: *DocumentStore,
    uri: []const u8,
    version: i32,
    languageId: []const u8,
    text: []const u8,
) !void {
    if (self.hasDocument(uri)) {
        std.log.info("Update document {s} (version = {d})", .{ uri, version });
        const doc = self.docs.getPtr(uri).?;
        const new_text = try self.alloc.dupe(u8, text);
        self.alloc.free(doc.*.text);
        doc.*.text = new_text;
        doc.*.version = version;
    } else {
        try self.addDocument(uri, version, languageId, text);
    }
}

pub fn removeDocument(self: *DocumentStore, uri: []const u8) void {
    std.log.info("Remove document {s}", .{uri});
    var entry = self.docs.getEntry(uri).?;
    entry.value_ptr.deinit(self.alloc);
    const key = entry.key_ptr.*;
    _ = self.docs.remove(uri);
    self.alloc.free(key);
}

pub fn getDocument(self: *DocumentStore, uri: []const u8) ?*Document {
    if (self.hasDocument(uri)) {
        return self.docs.getPtr(uri).?;
    } else {
        return null;
    }
}

test DocumentStore {
    const alloc = std.testing.allocator;
    var store = DocumentStore.init(alloc);
    defer store.deinit();

    const uri = "file:///foo/bar";
    const text = "hello world";
    const updated_text = "hello updated world";

    // Add
    try store.addDocument(uri, 1, "vmd", text);
    try std.testing.expect(store.hasDocument(uri));

    const doc = store.getDocument(uri).?;
    try std.testing.expectEqualStrings(text, doc.text);
    try std.testing.expectEqual(@as(i32, 1), doc.version);

    // Update
    try store.updateDocument(uri, 2, "", updated_text);
    try std.testing.expectEqualStrings(updated_text, store.getDocument(uri).?.text);
    try std.testing.expectEqual(@as(i32, 2), store.getDocument(uri).?.version);

    // Remove
    store.removeDocument(uri);
    try std.testing.expect(!store.hasDocument(uri));
}
