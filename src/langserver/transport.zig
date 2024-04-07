const std = @import("std");
const json_rpc = @import("json_rpc.zig");
const json = std.json;

/// Handles communication between client and server, including header parsing.
pub fn Transport(comptime Writer: type, comptime Reader: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        out: Writer,
        in: Reader,
        content_buffer: std.ArrayList(u8),

        pub fn init(
            allocator: std.mem.Allocator,
            out: Writer,
            in: Reader,
        ) Self {
            return .{
                .allocator = allocator,
                .out = out,
                .in = in,
                .content_buffer = std.ArrayList(u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.content_buffer.deinit();
        }

        /// Reads the next request from the client.
        pub fn readRequest(self: *Self) !json.Parsed(json_rpc.Request) {
            self.content_buffer.clearRetainingCapacity();
            try self.in.streamUntilDelimiter(self.content_buffer.writer(), ':', null);

            // TODO: Content-Type
            if (std.mem.eql(u8, self.content_buffer.items, "Content-Length")) {
                _ = try self.in.readByte(); // :

                self.content_buffer.clearRetainingCapacity();
                try self.in.streamUntilDelimiter(self.content_buffer.writer(), '\r', null);
                const content_length = try std.fmt.parseInt(usize, self.content_buffer.items, 10);

                _ = try self.in.skipBytes("\n\r\n".len, .{});

                self.content_buffer.clearRetainingCapacity();
                var content = try self.content_buffer.addManyAsSlice(content_length);
                _ = try self.in.readAtLeast(content, content_length);

                std.log.debug("Received request/notification: {s}", .{content});

                return json_rpc.Request.read(content, self.allocator);
            } else {
                std.log.err("Invalid header: {s}", .{self.content_buffer.items});
                return error.InvalidHeader;
            }
        }

        /// Writes a response to the client, with header part.
        pub fn writeResponse(self: *Self, response: anytype) !void {
            self.content_buffer.clearRetainingCapacity();
            try response.write(self.content_buffer.writer());
            std.log.debug("Sending response: {s}", .{self.content_buffer.items});
            try self.out.print("Content-Length: {}\r\n\r\n", .{self.content_buffer.items.len});
            try self.out.writeAll(self.content_buffer.items);
        }

        /// Writes a response to the client, with header part,
        /// overriding default stringify options
        pub fn writeResponseOverrideOptions(
            self: *Self,
            response: anytype,
            options: json.StringifyOptions,
        ) !void {
            self.content_buffer.clearRetainingCapacity();
            try response.writeOverrideOptions(self.content_buffer.writer(), options);
            std.log.debug("Sending response: {s}", .{self.content_buffer.items});
            try self.out.print("Content-Length: {}\r\n\r\n", .{self.content_buffer.items.len});
            try self.out.writeAll(self.content_buffer.items);
        }

        /// Writes a notification to the client, with header part.
        pub fn writeServerNotification(self: *Self, notification: anytype) !void {
            self.content_buffer.clearRetainingCapacity();
            try notification.write(self.content_buffer.writer());
            std.log.debug("Sending notification: {s}", .{self.content_buffer.items});
            try self.out.print("Content-Length: {}\r\n\r\n", .{self.content_buffer.items.len});
            try self.out.writeAll(self.content_buffer.items);
        }
    };
}

test "Transport.writeResponse" {
    const Reader = void;
    const Writer = std.ArrayList(u8).Writer;

    const Result = i32;
    const Error = json_rpc.Error(struct {});
    const Response = json_rpc.Response(Result, Error);

    const response = Response{ .id = .{ .integer = 1 }, .result = 42 };

    const expected_content = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}";
    const expected_header = "Content-Length: " ++ std.fmt.comptimePrint(
        "{d}\r\n\r\n",
        .{expected_content.len},
    );
    const expected = expected_header ++ expected_content;

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    var writer = out.writer();

    var transport = Transport(Writer, Reader).init(
        std.testing.allocator,
        writer,
        Reader{},
    );
    defer transport.deinit();

    try transport.writeResponse(response);
    try std.testing.expectEqualStrings(expected, out.items);
}

test "Transport.readRequest" {
    const Reader = std.io.FixedBufferStream([]const u8).Reader;
    const Writer = void;

    const Params = struct {
        foo: i32,
        bar: []const u8,
    };

    const request_content =
        \\{
        \\  "jsonrpc": "2.0",
        \\  "id": 1,
        \\  "method": "foo",
        \\  "params": {
        \\    "foo": 1,
        \\    "bar": "hello"
        \\  }
        \\}
    ;
    const request_header = "Content-Length: " ++ std.fmt.comptimePrint(
        "{d}\r\n\r\n",
        .{request_content.len},
    );
    const request_str = request_header ++ request_content;

    var stream = std.io.fixedBufferStream(request_str);
    const reader = stream.reader();

    var transport = Transport(Writer, Reader).init(
        std.testing.allocator,
        Writer{},
        reader,
    );
    defer transport.deinit();

    const request = try transport.readRequest();
    defer request.deinit();

    try std.testing.expectEqual(@as(i64, 1), request.value.id.?.integer);
    try std.testing.expectEqualStrings("foo", request.value.method);

    const params = try request.value.readParams(Params, std.testing.allocator);
    defer params.deinit();

    try std.testing.expectEqual(@as(i32, 1), params.value.foo);
    try std.testing.expectEqualStrings("hello", params.value.bar);
}

test "Transport.writeServerNotification" {
    const Reader = void;
    const Writer = std.ArrayList(u8).Writer;

    const Params = struct {
        foo: i32,
        bar: []const u8,
    };
    const Notification = json_rpc.ServerNotification(Params);

    const notification = Notification{ .method = "foo", .params = .{ .foo = 1, .bar = "hello" } };

    const expected_content = "{\"jsonrpc\":\"2.0\",\"method\":\"foo\",\"params\":{\"foo\":1,\"bar\":\"hello\"}}";
    const expected_header = "Content-Length: " ++ std.fmt.comptimePrint(
        "{d}\r\n\r\n",
        .{expected_content.len},
    );
    const expected = expected_header ++ expected_content;

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    var writer = out.writer();

    var transport = Transport(Writer, Reader).init(
        std.testing.allocator,
        writer,
        Reader{},
    );
    defer transport.deinit();

    try transport.writeServerNotification(notification);
    try std.testing.expectEqualStrings(expected, out.items);
}
