//!
//! Command line argument parsing
//!

const std = @import("std");

const LogOutput = enum { stderr, file, fifo };

const Options = struct {
    @"log-output": LogOutput = .stderr,
    @"log-file": []const u8 = "mclls.log",
};

const OptionsWithArgs = struct {
    @"log-output": void,
    @"log-file": void,
};

pub fn parseArgs() !Options {
    var options = Options{};

    var args = std.process.args();
    _ = args.skip();

    parse: while (args.next()) |arg| {
        inline for (@typeInfo(Options).Struct.fields) |field| {
            if (std.mem.eql(u8, arg, "--" ++ field.name)) {
                if (@hasField(OptionsWithArgs, field.name)) {
                    if (args.next()) |value| {
                        switch (field.type) {
                            []const u8 => @field(options, field.name) = value,
                            LogOutput => {
                                @field(options, field.name) = std.meta.stringToEnum(
                                    LogOutput,
                                    value,
                                ) orelse {
                                    return error.InvalidEnumValue;
                                };
                            },
                            else => unreachable,
                        }
                    } else {
                        return error.MissingArgument;
                    }
                }
                continue :parse;
            }
        }
        return error.InvalidArgument;
    }

    return options;
}
