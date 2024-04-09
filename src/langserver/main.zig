//!
//! The language server executable.
//!

const std = @import("std");
const Server = @import("Server.zig");
const utils = @import("utils.zig");
const Options = @import("Options.zig");

// Logging configuration.
// From https://ziglang.org/documentation/0.11.0/std/#A;std:log
pub const std_options = struct {
    // This is overriden by the global log_level
    pub const log_level = .debug;
    pub const logFn = logFnImpl;
};

pub fn logFnImpl(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (Options.instance.quiet) return;
    if (@intFromEnum(level) > @intFromEnum(Options.instance.@"log-level")) return;

    _ = scope;

    const prefix = "[" ++ comptime level.asText() ++ "] ";

    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();

    try Options.parseArgs();

    if (Options.instance.help) {
        try Options.usage(std.io.getStdOut().writer());
        std.os.exit(0);
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
