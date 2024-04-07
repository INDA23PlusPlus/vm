//!
//! The language server executable.
//!

const std = @import("std");
const Server = @import("Server.zig");
const utils = @import("utils.zig");

// Logging configuration.
// From https://ziglang.org/documentation/0.11.0/std/#A;std:log
pub const std_options = struct {
    // This is overriden by the global log_level
    pub const log_level = .debug;
    pub const logFn = logFnImpl;
};

var log_level: std.log.Level = .err;
const log_level_map = utils.TagNameMap(std.log.Level);

pub fn logFnImpl(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(log_level)) return;

    _ = scope;

    const prefix = "[" ++ comptime level.asText() ++ "] ";

    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();

    const options = @import("args.zig").parseArgs() catch |err| {
        std.log.err("Failed to parse arguments: {s}", .{@errorName(err)});
        std.os.exit(1);
    };

    if (options.@"log-level") |log_level_str| {
        log_level = log_level_map.get(log_level_str) orelse {
            std.log.err("Unknown log level: {s}", .{log_level_str});
            std.os.exit(1);
        };
        std.log.info("Log level set to: {s}", .{log_level_str});
    }

    var server = Server.init(
        gpa.allocator(),
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );

    server.run() catch |err| {
        std.log.err("Uncaught error: {s}", .{@errorName(err)});
        std.os.exit(1);
    };

    server.deinit();
    _ = gpa.deinit();
    std.os.exit(if (server.did_shutdown and server.did_exit) 0 else 1);
}
