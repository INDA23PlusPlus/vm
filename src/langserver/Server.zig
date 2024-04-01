//!
//! The language server.
//!

const Server = @This();

const std = @import("std");
const lsp = @import("lsp.zig");
const json_rpc = @import("json_rpc.zig");
const json = std.json;
const ErrorCode = @import("error.zig").Code;

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;
const Transport = @import("transport.zig").Transport(Writer, Reader);

transport: Transport,
alloc: std.mem.Allocator,

pub fn init(
    allocator: std.mem.Allocator,
    in: std.fs.File.Reader,
    out: std.fs.File.Writer,
) Server {
    return .{
        .transport = Transport.init(allocator, out, in),
        .alloc = allocator,
    };
}

pub fn deinit(self: *Server) void {
    self.transport.deinit();
}

pub fn run(self: *Server) !void {
    self.initLSP() catch |err| {
        std.log.err("Failed to initialize LSP: {s}", .{@errorName(err)});
        return;
    };

    while (true) {
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

        std.log.info("Received request with method name '{s}'", .{request.value.method});

        try self.handleRequest(&request.value);
        // TODO: internal error message
    }
}

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
        "Received initialize request from client '{s}'",
        .{params.value.clientInfo.?.name},
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

    switch (method) {
        // TODO: add method calls
        else => std.debug.panic("Method not implemented: {s}", .{@tagName(method)}),
    }
}
