//!
//! Generate VeMod instruction reference
//!

const std = @import("std");
const descr = @import("descr.zig");
const Format = enum { markdown };

const title = "VeMod Instruction Reference";

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    var format = Format.markdown;
    var output: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-f")) {
            const format_string = args.next() orelse {
                try stderr.print("error: Missing format argument\n", .{});
                return 1;
            };
            format = std.meta.stringToEnum(Format, format_string) orelse {
                try stderr.print(
                    "error: Unrecognized format \'{s}\'. Available formats are:\n",
                    .{format_string},
                );
                inline for (std.meta.fields(Format)) |field| {
                    try stderr.print("    * {s}\n", .{field.name});
                }
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "-o")) {
            output = args.next() orelse {
                try stderr.print("error: Missing output file argument\n", .{});
                return 1;
            };
        }
    }

    var writer: std.fs.File.Writer = undefined;
    var output_file: ?std.fs.File = null;
    defer if (output_file) |file| file.close();

    if (output) |output_| {
        output_file = std.fs.cwd().createFile(output_, .{}) catch |e| {
            try stderr.print(
                "error: Unable to create file {s}: {s}\n",
                .{ output_, @errorName(e) },
            );
            return 1;
        };
        writer = output_file.?.writer();
    } else {
        writer = stdout;
    }

    switch (format) {
        .markdown => try writeMarkdown(writer),
    }

    return 0;
}

fn writeMarkdown(writer: anytype) !void {
    try writer.print(
        \\# {s}
        \\
        \\|Opcode|Mnemonic|Description|Long description|
        \\|------|--------|-----------|----------------|
        \\
    , .{title});

    var descr_ptr = @constCast(&descr.text);
    var it = descr_ptr.iterator();
    while (it.next()) |kv| {
        // remove title from description
        var tk = std.mem.tokenizeScalar(u8, kv.value.*, '\n');
        const instr_title = tk.next().?["## ".len..];
        try writer.print(
            \\|{X:0>2}|`{s}`|{s}|
        , .{ @intFromEnum(kv.key), @tagName(kv.key), instr_title });

        while (tk.next()) |line| {
            try writer.writeAll(line);
            try writer.writeByte(' ');
        }
        try writer.writeAll("|\n");
    }
}
