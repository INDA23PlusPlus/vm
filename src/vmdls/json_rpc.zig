//!
//! JSON-RPC Object serialization and deserialization.
//! See https://www.jsonrpc.org/specification.
//!

const std = @import("std");
const json = std.json;

pub const default_stringify_options = std.json.StringifyOptions{
    .emit_null_optional_fields = false,
};
pub const default_parse_options = std.json.ParseOptions{
    .ignore_unknown_fields = true,
};

/// Used construct responses where the result or error is unused.
pub const Placeholder = struct {};

/// Compares two mesage id's for equality.
pub fn idEql(lhs: json.Value, rhs: json.Value) bool {
    if (lhs == .integer and rhs == .integer) {
        return lhs.integer == rhs.integer;
    } else if (lhs == .string and rhs == .string) {
        return std.mem.eql(u8, lhs.string, rhs.string);
    }
    return false;
}

/// Responses can be created statically as Zig structs.
/// They are parametrized by the result type.
pub fn Response(comptime Result: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: json.Value,
        result: ?Result = null,

        /// Write the response as JSON.
        /// Does not include the header part.
        pub fn write(self: @This(), writer: anytype) !void {
            const options = default_stringify_options;
            try std.json.stringify(self, options, writer);
        }

        // Write the response as JSON, but provide
        // custom stringify options.
        // Does not include the header part.
        pub fn writeOverrideOptions(
            self: @This(),
            writer: anytype,
            options: std.json.StringifyOptions,
        ) !void {
            try std.json.stringify(self, options, writer);
        }
    };
}

/// Response object for errors.
/// Error_ should be constructed from the Error function below.
pub fn ErrorResponse(comptime Error_: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: json.Value,
        @"error": Error_,

        /// Write the response as JSON.
        /// Does not include the header part.
        pub fn write(self: @This(), writer: anytype) !void {
            const options = default_stringify_options;
            try std.json.stringify(self, options, writer);
        }
    };
}

/// Error object parametrized by the associated data type.
pub fn Error(comptime Data: type) type {
    return struct {
        code: i32,
        message: []const u8,
        data: ?Data = null,
    };
}

/// The params field may be any structured JSON type.
/// To read it, use the readParams function.
pub const Request = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?json.Value = null,
    method: []const u8,
    params: ?json.Value = null,

    /// Read a request from a JSON string.
    /// The params field can be turned in to a Zig struct with `readParams`.
    pub fn read(s: []const u8, allocator: std.mem.Allocator) !json.Parsed(@This()) {
        // TODO
        const options = default_parse_options;
        return json.parseFromSlice(@This(), allocator, s, options);
    }

    /// Turns the params field into the provided Zig type.
    /// See tests for an example.
    pub fn readParams(
        self: @This(),
        comptime T: type,
        allocator: std.mem.Allocator,
    ) !json.Parsed(T) {
        return json.parseFromValue(
            T,
            allocator,
            self.params.?,
            default_parse_options,
        );
    }

    pub fn isNotification(self: @This()) bool {
        return self.id == null;
    }
};

/// Notification sent by the server
pub fn ServerNotification(comptime Params: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: []const u8,
        params: Params,

        pub fn write(self: @This(), writer: anytype) !void {
            const options = default_stringify_options;
            try std.json.stringify(self, options, writer);
        }
    };
}

test Response {
    const Result = struct {
        foo: i32,
        bar: []const u8,
    };

    const response = Response(Result){
        .id = .{ .integer = 1 },
        .result = .{
            .foo = 1,
            .bar = "hello",
        },
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try response.write(buffer.writer());
    try std.testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","id":1,"result":{"foo":1,"bar":"hello"}}
    ,
        buffer.items,
    );
}

test Request {
    const Params = struct {
        foo: i32,
        bar: []const u8,
    };

    const request_json =
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

    var request = try Request.read(request_json, std.testing.allocator);
    defer request.deinit();
    try std.testing.expectEqualStrings("foo", request.value.method);

    var params = try request.value.readParams(Params, std.testing.allocator);
    defer params.deinit();

    try std.testing.expectEqual(@as(i32, 1), params.value.foo);
    try std.testing.expectEqualStrings("hello", params.value.bar);
}

test ServerNotification {
    const Params = struct {
        foo: i32,
        bar: []const u8,
    };

    const notification = ServerNotification(Params){
        .method = "foo",
        .params = .{
            .foo = 1,
            .bar = "hello",
        },
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try notification.write(buffer.writer());
    try std.testing.expectEqualStrings(
        \\{"jsonrpc":"2.0","method":"foo","params":{"foo":1,"bar":"hello"}}
    ,
        buffer.items,
    );
}
