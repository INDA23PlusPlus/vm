//!
//! Command line argument parsing
//!

const std = @import("std");

const Options = struct {
    @"log-level": ?[]const u8 = null,
};

const OptionsWithArgs = struct {
    @"log-level": void,
};

pub fn parseArgs() !Options {
    var options = Options{};

    const stderr = std.io.getStdErr().writer();

    var args = std.process.args();
    _ = args.skip();

    parse: while (args.next()) |arg| {
        inline for (@typeInfo(Options).Struct.fields) |field| {
            if (std.mem.eql(u8, arg, "--" ++ field.name)) {
                if (@hasField(OptionsWithArgs, field.name)) {
                    if (args.next()) |value| {
                        switch (field.type) {
                            ?[]const u8 => @field(options, field.name) = value,
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

    return options;
}
