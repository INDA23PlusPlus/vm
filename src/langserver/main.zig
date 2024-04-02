//!
//! The language server executable.
//!

const std = @import("std");
const Server = @import("Server.zig");

// Logging configuration.
// From https://ziglang.org/documentation/0.11.0/std/#A;std:log
pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = logFnImpl;
};

var stderr: std.fs.File.Writer = undefined;

const use_log_file = true;

pub fn logFnImpl(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // const scope_prefix = "(" ++ switch (scope) {
    //     .my_project, .nice_library, std.log.default_log_scope => @tagName(scope),
    //     else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
    //         @tagName(scope)
    //     else
    //         return,
    // } ++ "): ";

    _ = scope;

    const prefix = "[" ++ comptime level.asText() ++ "] ";

    //std.debug.getStderrMutex().lock();
    //defer std.debug.getStderrMutex().unlock();
    //const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    if (use_log_file) {
        stderr = (try std.fs.cwd().createFile("langserver.log", .{})).writer();
    } else {
        stderr = std.io.getStdErr().writer();
    }

    var server = Server.init(
        gpa.allocator(),
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );
    defer server.deinit();

    try server.run();

    std.os.exit(if (server.did_shutdown) 0 else 1);
}
