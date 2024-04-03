//!
//! The language server.
//!

const Server = @This();

const std = @import("std");
const lsp = @import("lsp.zig");
const json_rpc = @import("json_rpc.zig");
const json = std.json;
const ErrorCode = @import("error.zig").Code;
const DocumentStore = @import("DocumentStore.zig");

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;
const Transport = @import("transport.zig").Transport(Writer, Reader);

transport: Transport,
alloc: std.mem.Allocator,
did_shutdown: bool = false,
did_exit: bool = false,
documents: DocumentStore,

pub fn init(
    allocator: std.mem.Allocator,
    in: std.fs.File.Reader,
    out: std.fs.File.Writer,
) Server {
    return .{
        .transport = Transport.init(allocator, out, in),
        .alloc = allocator,
        .documents = DocumentStore.init(allocator),
    };
}

pub fn deinit(self: *Server) void {
    self.transport.deinit();
    self.documents.deinit();
}

/// Main server loop
pub fn run(self: *Server) !void {
    self.initLSP() catch |err| {
        std.log.err("Failed to initialize LSP: {s}", .{@errorName(err)});
        return;
    };

    while (!self.did_exit) {
        std.log.info("Waiting for client request...", .{});

        const request = self.transport.readRequest() catch |err| {
            if (err == error.EndOfStream) {
                std.log.warn("Client disconnected", .{});
            } else {
                std.log.err("Failed to handle request: {s}", .{@errorName(err)});
            }
            return;
        };
        defer request.deinit();

        const msg_kind = if (request.value.isNotification()) "notification" else "request";
        std.log.info("Received {s} with method name '{s}'", .{ msg_kind, request.value.method });

        try self.handleRequest(&request.value);
        // TODO: internal error message
    }
}

/// Perform initial server-client handshake and declare capabilities.
fn initLSP(self: *Server) !void {
    std.log.info("Waiting for client init msg...", .{});

    const request = try self.transport.readRequest();
    defer request.deinit();

    std.debug.assert(lsp.Method.map.get(request.value.method) == .initialize);

    const params = try request.value.readParams(
        lsp.InitializeParams,
        self.alloc,
    );
    defer params.deinit();

    std.log.info(
        "Received initialize request from {s}",
        .{if (params.value.clientInfo) |info| info.name else "unknown client"},
    );

    const response = json_rpc.Response(lsp.InitializeResult, json_rpc.Placeholder){
        .id = request.value.id.?,
        .result = lsp.InitializeResult{},
    };
    try self.transport.writeResponse(response);

    const notification = try self.transport.readRequest();
    defer notification.deinit();

    std.debug.assert(notification.value.isNotification());
    std.debug.assert(lsp.Method.map.get(notification.value.method) == .initialized);

    std.log.info("Intialized. Happy coding!", .{});
}

fn sendErrorResponseWithNoData(
    self: *Server,
    id: json.Value,
    code: ErrorCode,
    message: []const u8,
) !void {
    const Error = json_rpc.Error(json_rpc.Placeholder);

    const response = json_rpc.Response(json_rpc.Placeholder, Error){
        .id = id,
        .@"error" = .{
            .code = @intFromEnum(code),
            .message = message,
        },
    };
    try self.transport.writeResponse(response);
}

fn handleRequest(self: *Server, request: *const json_rpc.Request) !void {
    const method = lsp.Method.map.get(request.method) orelse {
        if (!request.isNotification()) {
            try self.sendErrorResponseWithNoData(
                request.id.?,
                .MethodNotFound,
                "Method not found",
            );
        }
        return;
    };

    if (self.did_shutdown and method != .exit) {
        try self.sendErrorResponseWithNoData(
            request.id.?,
            .InvalidRequest,
            "Received request after server shutdown",
        );
        return;
    }

    switch (method) {
        .@"textDocument/didOpen" => try self.handleTextDocumentDidOpen(request),
        .@"textDocument/didChange" => try self.handleTextDocumentDidChange(request),
        .@"textDocument/didClose" => try self.handleTextDocumentDidClose(request),
        .@"textDocument/completion" => try self.handleTextDocumentCompletion(request),
        .shutdown => try self.handleShutdown(request),
        .exit => self.handleExit(),
        // TODO: add method calls
        else => {
            std.log.err("Unimplemented method: {s}", .{request.method});
            std.os.exit(1);
        },
    }
}

fn handleTextDocumentDidOpen(self: *Server, request: *const json_rpc.Request) !void {
    const params = try request.readParams(
        lsp.DidOpenTextDocumentParams,
        self.alloc,
    );
    defer params.deinit();

    std.log.info("Text document URI: {s}", .{params.value.textDocument.uri});
    std.log.info("Text document version: {d}", .{params.value.textDocument.version});

    try self.documents.updateDocument(
        params.value.textDocument.uri,
        params.value.textDocument.version,
        params.value.textDocument.languageId,
        params.value.textDocument.text,
    );

    const language = self.documents.getDocument(params.value.textDocument.uri).?.language;
    std.log.info("Language: {s}", .{if (language) |l| @tagName(l) else "unkown"});

    try self.publishDiagnostics(params.value.textDocument.uri);
}

fn handleTextDocumentDidChange(self: *Server, request: *const json_rpc.Request) !void {
    const params = try request.readParams(
        lsp.DidChangeTextDocumentParams,
        self.alloc,
    );
    defer params.deinit();

    try self.documents.updateDocument(
        params.value.textDocument.uri,
        params.value.textDocument.version,
        "", // no languageId provided
        params.value.contentChanges[0].text,
    );

    try self.publishDiagnostics(params.value.textDocument.uri);
}

fn handleTextDocumentDidClose(self: *Server, request: *const json_rpc.Request) !void {
    const params = try request.readParams(
        lsp.DidCloseTextDocumentParams,
        self.alloc,
    );
    defer params.deinit();

    // TODO: Error if document hasn't been opened.
    self.documents.removeDocument(params.value.textDocument.uri);
}

fn handleShutdown(self: *Server, request: *const json_rpc.Request) !void {
    self.did_shutdown = true;

    // This is an ugly hack dealing with the fact that we need to send result =
    // null, but `error` must not exists.

    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    switch (request.id.?) {
        .integer => |i| try stream.writer().print(
            "{{\"jsonrpc\": \"2.0\", \"id\": {d}, \"result\": null}}",
            .{i},
        ),
        .string => |s| try stream.writer().print(
            "{{\"jsonrpc\": \"2.0\", \"id\": \"{s}\", \"result\": null}}",
            .{s},
        ),
        else => unreachable,
    }
    const content = stream.getWritten();
    std.log.debug("Sending shutdown response: {s}", .{content});
    try self.transport.out.print("Content-Length: {d}\r\n\r\n{s}", .{ content.len, content });
}

fn handleExit(self: *Server) void {
    std.log.info("Exiting...", .{});
    self.did_exit = true;
}

fn publishDiagnostics(self: *Server, uri: []const u8) !void {
    var doc = self.documents.getDocument(uri).?;
    try doc.produceDiagnostics(self.alloc);

    const Notification = json_rpc.ServerNotification(lsp.PublishDiagnosticsParams);

    const notification = Notification{
        .method = @tagName(.@"textDocument/publishDiagnostics"),
        .params = .{
            .uri = uri,
            .version = doc.version,
            .diagnostics = doc.diagnostics.items,
        },
    };
    try self.transport.writeServerNotification(notification);
}

fn handleTextDocumentCompletion(self: *Server, request: *const json_rpc.Request) !void {
    const params = try request.readParams(
        lsp.CompletionParams,
        self.alloc,
    );
    defer params.deinit();

    var list = std.ArrayList(lsp.CompletionItem).init(self.alloc);
    defer list.deinit();

    const doc = self.documents.getDocument(params.value.textDocument.uri) orelse {
        // TODO: error response on non-existent document
        unreachable;
    };

    const text = doc.text;
    const lang = doc.language;

    if (lang == .vmd) {
        try @import("vmd_completion.zig").computeCompletions(
            params.value.position,
            text,
            &list,
        );
    }

    const Response = json_rpc.Response(lsp.CompletionList, json_rpc.Placeholder);
    const response = Response{
        .id = request.id.?,
        .result = lsp.CompletionList{
            .items = list.items,
        },
    };
    try self.transport.writeResponse(response);
}
