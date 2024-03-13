//!
//! The intermediate language assembler executable.
//!

const std = @import("std");
const Token = @import("Token.zig");
const Error = @import("Error.zig");
const SourceRef = @import("SourceRef.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var input: std.fs.File.Reader = std.io.getStdIn().reader();
    var output: std.fs.File.Writer = std.io.getStdOut().writer();

    while (args.next()) |arg| {
        if (arg[0] == '-') {
            // Output file
            if (std.mem.eql(u8, arg, "-o")) {
                const output_filename = args.next() orelse {
                    std.debug.print("No output file specified.\n", .{});
                    std.os.exit(1);
                };
                output = (std.fs.cwd().createFile(output_filename, .{}) catch {
                    std.debug.print("Could not create output file: {s}\n", .{output_filename});
                    std.os.exit(1);
                }).writer();
            }
        } else {
            // Read from file.
            input = (std.fs.cwd().openFile(arg, .{}) catch {
                std.debug.print("Could not open input file: {s}\n", .{arg});
                std.os.exit(1);
            }).reader();
        }
    }

    const source = try input.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    var errors = std.ArrayList(Error).init(allocator);
    defer errors.deinit();

    var scanner: Token.Scanner = .{ .source = source, .errors = &errors };

    while (try scanner.next()) |token| {
        std.debug.print("{s}: {s}", .{ @tagName(token.tag), token.where });
        if (token.tag == .instr) {
            std.debug.print(" ({s}), has operand: {s}\n", .{
                @tagName(token.tag.instr),
                if (token.tag.instr.hasOperand()) "yes" else "no",
            });
        } else {
            std.debug.print("\n", .{});
        }
    }

    for (errors.items) |err| {
        try err.print(source, output);
    }
}