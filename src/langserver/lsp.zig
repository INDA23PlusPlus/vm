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

const server_name = "mclls";

pub const Method = enum {
    initialize,
    initialized,
    shutdown,
    exit,
    @"textDocument/didOpen",
    @"textDocument/didClose",
    @"textDocument/didChange",
    @"textDocument/publishDiagnostics",
    @"textDocument/completion",
    @"textDocument/hover",
    // TODO: add methods as needed.

    pub const map = utils.TagNameMap(@This());
};

// *******************************************
//              INITIALIZATION
// *******************************************

pub const InitializeParams = struct {
    clientInfo: ?struct {
        name: []const u8,
        version: ?[]const u8 = null,
    } = null,
};

pub const InitializeErrorData = struct {
    retry: bool = false,
};

pub const TextDocumentSyncKind = enum(i32) {
    None = 0,
    Full = 1,
    Incremental = 2,
};

pub const CompletionOptions = struct {
    triggerCharacters: ?[]const []const u8 = &.{"-"},
    // I don't know what the rest of the fields mean
};

pub const ServerCapabilities = struct {
    textDocumentSync: ?i32 = @intFromEnum(TextDocumentSyncKind.Full),
    completionProvider: ?CompletionOptions = CompletionOptions{},
    hoverProvider: ?bool = true,

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

pub const DidChangeTextDocumentParams = struct {
    textDocument: struct {
        uri: []const u8,
        version: i32,
    },
    contentChanges: []struct {
        // We only receive the full document, not a range.
        text: []const u8,
    },
};

pub const DidCloseTextDocumentParams = struct {
    textDocument: struct {
        uri: []const u8,
    },
};

// *******************************************
//              DIAGNOSTICS
// *******************************************

pub const DiagnosticSeverity = enum(i32) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

pub const Position = struct {
    line: i32,
    character: i32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: []const u8,
};

pub const Diagnostic = struct {
    range: Range,
    severity: ?i32 = null,
    code: ?i32 = null,
    source: ?[]const u8 = null,
    message: []const u8,
    relatedInformation: ?[]DiagnosticRelatedInformation = null,
};

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    version: ?i32 = null,
    diagnostics: []Diagnostic,
};

// *******************************************
//                 COMPLETION
// *******************************************

pub const CompletionItemKind = enum(i32) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: ?i32 = null,
    detail: ?[]const u8 = null,
};

pub const CompletionList = struct {
    items: []CompletionItem,
    // TODO: what does this mean
    isIncomplete: bool = true,
};

pub const CompletionParams = struct {
    textDocument: struct {
        uri: []const u8,
    },
    position: Position,
};

// *******************************************
//                HOVER
// *******************************************

pub const HoverParams = struct {
    textDocument: struct {
        uri: []const u8,
    },
    position: Position,
};

pub const Hover = struct {
    contents: []const u8,
    range: ?Range = null,
};
