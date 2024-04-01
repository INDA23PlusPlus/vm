//!
//! LSP specific defintions and utilities.
//! See https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
//!
//! Commented out fields are not currently used by this implementation and are ignored when parsing requests.
//!

const std = @import("std");
const utils = @import("utils.zig");
const json_rpc = @import("json_rpc.zig");
const json = std.json;

const server_name = "the_cool_language_server_that_shows_you_what_you_did_wrong";

pub const Method = enum {
    initialize,
    initialized,
    shutdown,
    @"textDocument/didOpen",
    @"textDocument/didClose",
    @"textDocument/didChange",
    // TODO: add methods as needed.

    pub const map = utils.TagNameMap(@This());
};

//pub const ClientCapabilities = struct {};

//pub const TraceValue = struct {};

// *******************************************
//              INITIALIZATION
// *******************************************

// ===============================================================================
//
// The initialize request is sent as the first request from the client to the
// server. If the server receives a request or notification before the initialize
// request it should act as follows:
//
// * For a request the response should be an error with code: -32002. The message
//   can be picked by the server.
// * Notifications should be dropped, except for the exit notification. This
//   will allow the exit of a server without an initialize request.
//
// ===============================================================================

///
/// Method: initialize
///
pub const InitializeParams = struct {
    //processId: ?i32 = null,
    clientInfo: ?struct {
        name: []const u8,
        version: ?[]const u8 = null,
    },
    //locale: ?[]const u8 = null,
    //rootPath: ?[]const u8 = null,
    //rootUri: ?[]const u8 = null,
    //initializationOptions: ?json.Value = null,
    //capabilities: ?ClientCapabilities = null,
    //trace: ?TraceValue = null,
    //workspaceFolders: ?std.ArrayList(json.Value),

};

pub const InitializeErrorData = struct {
    retry: bool = false,
};

pub const TextDocumentSyncKind = enum(i32) {
    None = 0,
    Full = 1,
    Incremental = 2,
};

pub const ServerCapabilities = struct {
    textDocumentSync: ?i32 = @intFromEnum(TextDocumentSyncKind.Full),
    // TODO: Add more capabilities as needed.
};

const ServerInfo = struct {
    name: []const u8 = server_name,
    version: ?[]const u8 = null,
};

pub const InitializeResult = struct {
    capabilities: ?ServerCapabilities = ServerCapabilities{},
    serverInfo: ?ServerInfo = ServerInfo{},
};

// *******************************************
//       TEXT DOCUMENT SYNCHRONIZATION
// *******************************************

pub const DidOpenTextDocumentParams = struct {
    textDocument: struct {
        uri: []const u8,
        languageId: []const u8,
        version: i32,
        text: []const u8,
    },
};
