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

    // For formatting error messages
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    while (!self.did_exit) {
        stream.reset();
        std.log.info("Waiting for client request...", .{});

        // Read request, or send apporiate error response if it fails
        const request = self.transport.readRequest() catch |err| {
            if (err == error.EndOfStream) {
                std.log.warn("Client disconnected", .{});
            } else {
                try stream.writer().print(
                    "Failed to parse request: {s}\n",
                    .{@errorName(err)},
                );
                std.log.err("{s}", .{stream.getWritten()});
                try self.sendErrorResponseWithNoData(
                    json.Value.null,
                    ErrorCode.ParseError,
                    stream.getWritten(),
                );
                continue;
            }
            return;
        };
        defer request.deinit();

        const msg_kind = if (request.value.isNotification()) "notification" else "request";
        std.log.info("Received {s} with method name '{s}'", .{ msg_kind, request.value.method });

        // Handle request, or send apporiate error response if it fails
        self.handleRequest(&request.value) catch |err| {
            const err_msg_pair = switch (err) {
                json.ParseFromValueError.UnknownField,
                json.ParseFromValueError.MissingField,
                json.ParseFromValueError.DuplicateField,
                => .{ ErrorCode.InvalidRequest, "Invalid request format" },
                else => blk: {
                    try stream.writer().print(
                        "Failed to handle request: {s}\n",
                        .{@errorName(err)},
                    );
                    break :blk .{ ErrorCode.RequestFailed, stream.getWritten() };
                },
            };
            std.log.err("{s}", .{err_msg_pair.@"1"});
            try self.sendErrorResponseWithNoData(
                request.value.id.?,
                err_msg_pair.@"0",
                err_msg_pair.@"1",
            );
        };
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

    const init_result = lsp.InitializeResult{};
    std.log.info("Supported capabilities:", .{});
    inline for (std.meta.fields(lsp.ServerCapabilities)) |field| {
        if (@field(init_result.capabilities.?, field.name) != null) {
            std.log.info("  {s}", .{field.name});
        }
    }

    const response = json_rpc.Response(lsp.InitializeResult){
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

    const response = json_rpc.ErrorResponse(Error){
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
        .@"textDocument/hover" => try self.handleTextDocumentHover(request),
        .shutdown => try self.handleShutdown(request),
        .exit => self.handleExit(),
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
    self.documents.deinit();
    try self.sendNullResultResponse(request.id.?);
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

    const Response = json_rpc.Response(lsp.CompletionList);
    const response = Response{
        .id = request.id.?,
        .result = lsp.CompletionList{
            .items = list.items,
        },
    };
    try self.transport.writeResponse(response);
}

fn handleTextDocumentHover(self: *Server, request: *const json_rpc.Request) !void {
    const params = try request.readParams(
        lsp.HoverParams,
        self.alloc,
    );
    defer params.deinit();

    const doc = self.documents.getDocument(params.value.textDocument.uri) orelse {
        // TODO: error response on non-existent document
        unreachable;
    };

    const text = doc.text;
    const lang = doc.language;

    var hover: ?lsp.Hover = null;

    if (lang == .vmd) {
        hover = try @import("vmd_hover.zig").getHoverInfo(
            text,
            params.value.position,
            self.alloc,
        );
    }

    if (hover) |h| {
        std.log.info("Providing hover information: {s}", .{h.contents});
        const Response = json_rpc.Response(lsp.Hover);
        const response = Response{
            .id = request.id.?,
            .result = h,
        };
        try self.transport.writeResponse(response);
    } else {
        std.log.info("No hover information available", .{});
        try self.sendNullResultResponse(request.id.?);
    }
}

fn sendNullResultResponse(self: *Server, id: json.Value) !void {
    const Response = json_rpc.Response(json_rpc.Placeholder);
    const response = Response{
        .id = id,
        .result = null,
    };
    var options = json_rpc.default_stringify_options;
    options.emit_null_optional_fields = true;
    try self.transport.writeResponseOverrideOptions(response, options);
}
