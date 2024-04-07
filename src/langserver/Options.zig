//!
//! Command line argument parsing
//!

const std = @import("std");
const Options = @This();

@"log-level": std.log.Level = .err,
disable: std.EnumSet(Feature) = std.EnumSet(Feature).initEmpty(),

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
                                    return error.InvalidArgument;
                                }
                            },
                            std.EnumSet(Feature) => {
                                if (std.meta.stringToEnum(Feature, value)) |feature| {
                                    instance.disable.insert(feature);
                                } else {
                                    try stderr.print("Invalid feature: {s}\n", .{value});
                                    return error.InvalidArgument;
                                }
                            },
                            else => @compileError("Invalid option type"),
                        }
                    } else {
                        try stderr.print("Missing argument for {s}\n", .{arg});
                        return error.MissingArgument;
                    }
                }
                continue :parse;
            }
        } else {
            try stderr.print("Invalid option: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }
}
