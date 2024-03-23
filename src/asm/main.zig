//!
//! The intermediate language assembler executable.
//!

const std = @import("std");
const Error = @import("Error.zig");
const Asm = @import("Asm.zig");

pub fn usage() !void {
    var stderr = std.io.getStdErr().writer();
    try stderr.print("Usage: asm [options]\n\nOptions:\n", .{});
    try stderr.print("  -h, --help         Print this help and exit\n", .{});
    try stderr.print("  -o, --output FILE  Write output to FILE (defaults to stdout)\n", .{});
    try stderr.print("  -i, --input FILE   Read input from FILE (defaults to stdin)\n", .{});
    std.os.exit(1);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var input = std.io.getStdIn();
    var output = std.io.getStdOut();
    var stderr = std.io.getStdErr().writer();

    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try usage();
        }

        if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            if (args.next()) |input_file_name| {
                input = std.fs.cwd().openFile(input_file_name, .{}) catch |err| {
                    try stderr.print("Failed to open input file: {}\n", .{err});
                    std.os.exit(1);
                };
            } else {
                try stderr.print("Expected argument after \"{s}\"\n", .{arg});
                try usage();
            }
            continue;
        }

        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (args.next()) |output_file_name| {
                output = std.fs.cwd().createFile(output_file_name, .{}) catch |err| {
                    try stderr.print("Failed to create output file: {}\n", .{err});
                    std.os.exit(1);
                };
            } else {
                try stderr.print("Expected argument after \"{s}\"\n", .{arg});
                try usage();
            }
            continue;
        }

        try stderr.print("Unknown option: {s}\n", .{arg});
        try usage();
    }

    const source = input.reader().readAllAlloc(gpa.allocator(), std.math.maxInt(usize)) catch |err| {
        try stderr.print("Failed to read input: {}\n", .{err});
        std.os.exit(1);
    };

    var errors = std.ArrayList(Error).init(gpa.allocator());
    defer errors.deinit();

    var asm_ = Asm.init(source, gpa.allocator(), &errors);
    defer asm_.deinit();

    try asm_.assemble();

    if (errors.items.len > 0) {
        for (errors.items) |err| {
            try err.print(source, stderr);
        }
        std.os.exit(1);
    }

    try asm_.emit(output.writer());
}
