//!
//! Blue language REPL
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const io = std.io;
const ArrayList = std.ArrayList;
const ascii = std.ascii;
const mem = std.mem;

const blue = @import("blue");
const Compilation = blue.Compilation;
const Ast = blue.Ast;

const asm_ = @import("asm");
const Asm = asm_.Asm;
const EmbeddedSourceOptions = Asm.EmbeddedSourceOptions;

const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;

const vm = @import("vm");
const VMContext = vm.VMContext;
const interpreter = vm.interpreter;

const print_rterror = @import("main.zig").print_rterror;

const ln = @cImport({
    @cInclude("linenoise.h");
});

fn isOnlyWhitespace(str: []const u8) bool {
    for (str) |c| {
        if (!ascii.isWhitespace(c)) {
            return false;
        }
    } else return true;
}

// we need to modify the AST so that
// the user provided expression is printed,
// and the real expression evaluates to an integer (0).
fn astOverlay(ast: *Ast) !void {
    const println = try ast.push(.{ .println = ast.root });
    const zero = try ast.push(.{ .number = .{ .tag = .int, .where = "0" } });
    const compound = try ast.push(.{ .compound = .{ .discard = println, .keep = zero } });
    ast.root = compound;
}

pub fn main(
    allocator: Allocator,
    stdout: anytype,
    stdin: anytype,
    stderr: anytype,
    no_color: bool,
) !void {
    _ = stderr;
    _ = stdin;

    var input_buffer = ArrayList(u8).init(allocator);
    defer input_buffer.deinit();

    repl: while (true) {
        input_buffer.clearRetainingCapacity();

        var first = true;

        while (true) {
            const prompt = if (first) ">>> " else "    ";
            first = false;

            const cstr = ln.linenoise(prompt);
            if (@as(?*anyopaque, cstr) == ln.NULL) return;
            _ = ln.linenoiseHistoryAdd(cstr);
            const line = std.mem.span(cstr);

            if (line.len == 0) {
                ln.linenoiseFree(cstr);
                break;
            }

            try input_buffer.appendSlice(line);
            try input_buffer.append('\n');
            ln.linenoiseFree(cstr);

            const maybe_cmd = mem.trim(u8, input_buffer.items, " \n\t");
            if (mem.eql(u8, maybe_cmd, "clear")) {
                try stdout.writeAll("\x1b[2J");
                continue :repl;
            } else if (mem.eql(u8, maybe_cmd, "exit")) {
                return;
            }
        }

        // ignore empty input
        if (isOnlyWhitespace(input_buffer.items)) continue;

        // evaluate the expression
        {
            const source = input_buffer.items;

            var diagnostics = DiagnosticList.init(allocator, source);
            diagnostics.no_color = no_color;
            defer diagnostics.deinit();
            var compilation = blue.compile(
                source,
                allocator,
                &diagnostics,
                false,
                astOverlay,
            ) catch {
                try diagnostics.printAllDiagnostic(stdout);
                continue;
            };
            defer compilation.deinit();

            var assembler = Asm.init(compilation.result, allocator, &diagnostics);
            defer assembler.deinit();
            try assembler.assemble();
            if (diagnostics.hasDiagnosticsMinSeverity(.Hint)) {
                try diagnostics.printAllDiagnostic(stdout);
                if (diagnostics.hasDiagnosticsMinSeverity(.Error)) continue;
            }

            const src_opts: EmbeddedSourceOptions = .{
                .frontend = .{
                    .tokens = compilation.tokens,
                    .source = source,
                },
            };
            var program = try assembler.getProgram(allocator, src_opts);
            defer program.deinit();

            var context = try VMContext.init(program, allocator, &stdout, &stdout, false);
            defer context.deinit();

            _ = interpreter.run(&context) catch |err| {
                if (context.rterror) |rterror| {
                    try print_rterror(program, rterror, stdout, no_color);
                } else {
                    return err;
                }
            };
        }
    }
}
