//!
//! Blue language REPL
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const io = std.io;
const ArrayList = std.ArrayList;
const ascii = std.ascii;

const blue = @import("blue");
const Compilation = blue.Compilation;
const Ast = blue.Ast;

const asm_ = @import("asm");
const Asm = asm_.Asm;
const Error = asm_.Error;
const EmbeddedSourceOptions = Asm.EmbeddedSourceOptions;

const vm = @import("vm");
const VMContext = vm.VMContext;
const interpreter = vm.interpreter;

const print_rterror = @import("main.zig").print_rterror;

fn isOnlyWhitespace(str: []const u8) bool {
    for (str) |c| {
        if (!ascii.isWhitespace(c)) {
            return false;
        }
    } else return true;
}

const input_prefix = ">>> ";

// we need to modify the AST so that
// the user provided expression is printed,
// and the real expression evaluates to an integer (0).
fn astOverlay(ast: *Ast) !void {
    const print = try ast.push(.{ .print = ast.root });
    const zero = try ast.push(.{ .number = .{ .tag = .int, .where = "0" } });
    const compound = try ast.push(.{ .compound = .{ .discard = print, .keep = zero } });
    ast.root = compound;
}

pub fn main(
    allocator: Allocator,
    stdout: anytype,
    stdin: anytype,
    stderr: anytype,
) !void {
    _ = stderr;
    var input_buffer = ArrayList(u8).init(allocator);
    defer input_buffer.deinit();

    while (true) {
        input_buffer.clearRetainingCapacity();

        try stdout.writeAll(input_prefix);

        while (true) {
            // keep reading until we receive empty line, or terminate REPL on EOF
            const buffer_len_before_input_line = input_buffer.items.len;
            stdin.streamUntilDelimiter(input_buffer.writer(), '\n', null) catch {
                try stdout.writeByte('\n');
                return;
            };
            if (input_buffer.items.len == buffer_len_before_input_line) break;
            try input_buffer.append('\n');

            // align cursor with previous line
            try stdout.print("\x1B[{d}C", .{input_prefix.len});
        }

        // ignore empty input
        if (isOnlyWhitespace(input_buffer.items)) continue;

        // evaluate the expression
        {
            const source = input_buffer.items;

            var errors = ArrayList(Error).init(allocator);
            defer errors.deinit();
            var compilation = blue.compile(
                source,
                allocator,
                &errors,
                false,
                astOverlay,
            ) catch {
                for (errors.items) |err| {
                    try err.print(source, stdout);
                }
                continue;
            };
            defer compilation.deinit();

            var assembler = Asm.init(compilation.result, allocator, &errors);
            defer assembler.deinit();
            try assembler.assemble();
            if (errors.items.len > 0) {
                for (errors.items) |err| {
                    try err.print(source, stdout);
                }
                continue;
            }

            const src_opts: EmbeddedSourceOptions = .{
                .frontend = .{
                    .tokens = compilation.tokens,
                    .source = source,
                },
            };
            var program = try assembler.getProgram(allocator, src_opts);
            defer program.deinit();

            var context = VMContext.init(program, allocator, &stdout, &stdout, false);
            defer context.deinit();

            _ = interpreter.run(&context) catch |err| {
                if (context.rterror) |rterror| {
                    try print_rterror(program, rterror, stdout);
                } else {
                    return err;
                }
            };
        }
    }
}
