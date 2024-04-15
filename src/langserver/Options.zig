//!
//! Command line argument parsing
//!

const std = @import("std");
const Options = @This();

@"log-level": std.log.Level = .err,
disable: std.EnumSet(Feature) = std.EnumSet(Feature).initEmpty(),
quiet: bool = false,
help: bool = false,

pub fn usage(writer: anytype) !void {
    try writer.print(
        \\Usage:
        \\    mclls <options>
        \\
        \\Options:
        \\    --quiet                 Suppress log output.
        \\    --log-level <level>     Set log level to <level>. Can be one of
        \\                            `err`, `warn`, `info`, `debug`. Default is
        \\                            `err`.
        \\    --disable <feature>     Disables <feature>. Can be one of `hover`,
        \\                            `diagnostics`, `completion`. All features
        \\                            are enabled by default.
        \\    --help                  Display this message and exit.
        \\
    , .{});
}

pub var instance: Options = .{};

const Feature = enum { hover, completion, diagnostics };

const OptionsWithArgs = struct {
    @"log-level": void,
    disable: void,
};

pub fn parseArgs() !void {
    const stderr = std.io.getStdErr().writer();

    var args = std.process.args();
    _ = args.skip();

    parse: while (args.next()) |arg| {
        inline for (@typeInfo(Options).Struct.fields) |field| {
            if (std.mem.eql(u8, arg, "--" ++ field.name)) {
                if (@hasField(OptionsWithArgs, field.name)) {
                    if (args.next()) |value| {
                        switch (field.type) {
                            std.log.Level => {
                                if (std.meta.stringToEnum(std.log.Level, value)) |level| {
                                    instance.@"log-level" = level;
                                } else {
                                    try stderr.print("Invalid log level: {s}\n", .{value});
                                    try usage(stderr);
                                    return error.InvalidArgument;
                                }
                            },
                            std.EnumSet(Feature) => {
                                if (std.meta.stringToEnum(Feature, value)) |feature| {
                                    instance.disable.insert(feature);
                                } else {
                                    try stderr.print("Invalid feature: {s}\n", .{value});
                                    try usage(stderr);
                                    return error.InvalidArgument;
                                }
                            },
                            else => @compileError("Invalid option type"),
                        }
                    } else {
                        try stderr.print("Missing argument for {s}\n", .{arg});
                        try usage(stderr);
                        return error.MissingArgument;
                    }
                } else {
                    if (field.type != bool) {
                        @compileError("Option without argument must be boolean");
                    }
                    @field(instance, field.name) = true;
                }
                continue :parse;
            }
        } else {
            try stderr.print("Invalid option: {s}\n", .{arg});
            try usage(stderr);
            return error.InvalidArgument;
        }
    }
}
