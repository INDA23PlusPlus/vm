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
    text: []const u8,
) !void {
    std.log.info("Add document {s} (version = {d})", .{ uri, version });

    const key = try self.alloc.dupe(u8, uri);
    errdefer self.alloc.free(key);

    var doc = try Document.init(self.alloc, key, version, text);
    errdefer doc.deinit(self.alloc);

    try self.docs.put(key, doc);
}

pub fn hasDocument(self: *DocumentStore, uri: []const u8) bool {
    return self.docs.contains(uri);
}

pub fn updateDocument(self: *DocumentStore, uri: []const u8, version: i32, text: []const u8) !void {
    if (self.hasDocument(uri)) {
        // TODO: something something errdefer
        std.log.info("Update document {s} (version = {d})", .{ uri, version });
        var doc = self.docs.getPtr(uri).?;
        doc.*.version = version;
        self.alloc.free(doc.*.text);
        doc.*.text = try self.alloc.dupe(u8, text);
    } else {
        try self.addDocument(uri, version, text);
    }
}

pub fn removeDocument(self: *DocumentStore, uri: []const u8) void {
    // TODO: assert it exists
    std.log.info("Remove document {s}", .{uri});
    var entry = self.docs.getEntry(uri).?;
    entry.value_ptr.deinit(self.alloc);
    var key = entry.key_ptr.*;
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
    var alloc = std.testing.allocator;
    var store = DocumentStore.init(alloc);
    defer store.deinit();

    var uri = "file:///foo/bar";
    var text = "hello world";
    var updated_text = "hello updated world";

    // Add
    try store.addDocument(uri, 1, text);
    try std.testing.expect(store.hasDocument(uri));

    var doc = store.getDocument(uri).?;
    try std.testing.expectEqualStrings(text, doc.text);
    try std.testing.expectEqual(@as(i32, 1), doc.version);

    // Update
    try store.updateDocument(uri, 2, updated_text);
    try std.testing.expectEqualStrings(updated_text, store.getDocument(uri).?.text);
    try std.testing.expectEqual(@as(i32, 2), store.getDocument(uri).?.version);

    // Remove
    store.removeDocument(uri);
    try std.testing.expect(!store.hasDocument(uri));
}
