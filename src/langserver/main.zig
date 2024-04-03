//!
//! The language server executable.
//!

const std = @import("std");
const Server = @import("Server.zig");

const c = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("sys/types.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
});

// Logging configuration.
// From https://ziglang.org/documentation/0.11.0/std/#A;std:log
pub const std_options = struct {
    pub const log_level = .info;
    pub const logFn = logFnImpl;
};

var log_writer: std.fs.File.Writer = undefined;

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

    nosuspend log_writer.print(prefix ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const options = try @import("args.zig").parseArgs();

    switch (options.@"log-output") {
        .fifo => {
            // TODO: make this cross platform
            // TODO: make this a command line option
            // TODO: check return codes
            // TODO: maybe don't do this at all
            var cstr = try gpa.allocator().dupeZ(u8, options.@"log-file");
            defer gpa.allocator().free(cstr);
            _ = c.mkfifo(cstr, 0o666);
            var log_file = try std.fs.cwd().openFile(
                options.@"log-file",
                .{ .mode = .write_only },
            );
            log_writer = log_file.writer();
        },
        .stderr => {
            log_writer = std.io.getStdErr().writer();
        },
        .file => {
            var log_file = try std.fs.cwd().createFile(options.@"log-file", .{});
            log_writer = log_file.writer();
        },
    }

    std.log.info("Log output: {s} {s}", .{
        @tagName(options.@"log-output"),
        if (options.@"log-output" != .stderr) options.@"log-file" else "",
    });

    var server = Server.init(
        gpa.allocator(),
        std.io.getStdIn().reader(),
        std.io.getStdOut().writer(),
    );
    defer server.deinit();

    try server.run();

    std.os.exit(if (server.did_shutdown) 0 else 1);
}
