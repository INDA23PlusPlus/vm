//!
//! The main VeMod executable.
//!

const std = @import("std");
const process = std.process;
const mem = std.mem;
const io = std.io;
const meta = std.meta;
const fs = std.fs;
const heap = std.heap;
const ArrayList = std.ArrayList;

const arch = @import("arch");
const Program = arch.Program;
const RtError = arch.err.RtError;

const asm_ = @import("asm");
const Asm = asm_.Asm;

const diagnostic = @import("diagnostic");
const DiagnosticList = diagnostic.DiagnosticList;
const SourceRef = diagnostic.SourceRef;

const binary = @import("binary");

const vm = @import("vm");
const Context = vm.VMContext;
const interpreter = vm.interpreter;

const blue = @import("blue");

const Jit = @import("jit").Jit;

const repl = @import("repl.zig");

const Extension = enum { vmd, mcl, vbf, blue };

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = logFn,
};

fn getExtension(filename: []const u8, basename: *?[]const u8) ?Extension {
    if (filename.len == 0) return null;
    var iter = mem.tokenizeScalar(u8, filename, '.');
    var ext: []const u8 = undefined;
    while (iter.next()) |tok| ext = tok;
    basename.* = filename[0 .. filename.len - ext.len - 1];
    return meta.stringToEnum(Extension, ext);
}

const Options = struct {
    action: enum { compile, run } = .run,
    output_filename: ?[]const u8 = null,
    input_filename: ?[]const u8 = null,
    input_basename: ?[]const u8 = null,
    extension: ?Extension = null,
    strip: bool = false,
    jit: bool = false,
    output_asm: bool = false,
    cl_expr: ?[]const u8 = null,
};

fn usage(name: []const u8) !void {
    try io.getStdOut().writer().print(
        \\Usage:
        \\    {s} INPUT [OPTIONS...]
        \\
        \\Options:
        \\    -c, --compile            Only compile.
        \\                              Writes program to binary file specified by OUTPUT.
        \\    -t, --transpile          Only transpile.
        \\                              Write generated VeMod assembly to OUTPUT instead of compiled program.
        \\                              Ignored if input is binary or VeMod assembly.
        \\    -o, --output OUTPUT      Write output to file OUTPUT.
        \\                              If omitted, output filename is inferred from input filename.
        \\    -s, --strip              Don't include source information in compiled program.
        \\    -j, --jit                Use experimental JIT recompiler.
        \\    -h, --help               Show this help message and exit.
        \\    -p, --parse "EXPR"       Parse Blue expression from command line, surrounded by double quotes.
        \\                              Overrides any provided file input.
        \\    -r, --repl               Run the Blue REPL.
        \\
    , .{name});
}

pub fn print_rterror(prog: Program, rte: RtError, writer: anytype) !void {
    if (prog.tokens == null or rte.pc == null) {
        _ = try writer.write("Runtime error: ");
        try rte.err.print(writer);
        return;
    }

    const source = prog.deinit_data.?.source.?;
    const token = prog.tokens.?[rte.pc.?];
    const ref = try SourceRef.init(source, token);

    try writer.print("Runtime error (line {d}): ", .{ref.line_num});
    try rte.err.print(writer);
    try ref.print(writer, SourceRef.terminal_colors.red);
}

pub fn main() !u8 {

    // Parse command line options
    var options = Options{};

    var args = process.args();
    const name = args.next().?;

    const stdin = io.getStdIn().reader();
    const stdout = io.getStdOut().writer();
    const stderr = io.getStdErr().writer();

    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var name_buffer = ArrayList(u8).init(allocator);
    defer name_buffer.deinit();

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-c") or mem.eql(u8, arg, "--compile")) {
            options.action = .compile;
        } else if (mem.eql(u8, arg, "-o") or mem.eql(u8, arg, "--output")) {
            options.output_filename = args.next() orelse {
                try usage(name);
                try stderr.print("error: missing output file name\n", .{});
                return 1;
            };
        } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            try usage(name);
            return 0;
        } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--strip")) {
            options.strip = true;
        } else if (mem.eql(u8, arg, "-j") or mem.eql(u8, arg, "--jit")) {
            options.jit = true;
        } else if (mem.eql(u8, arg, "-t") or mem.eql(u8, arg, "--transpile")) {
            options.output_asm = true;
        } else if (mem.eql(u8, arg, "-p") or mem.eql(u8, arg, "--parse")) {
            options.cl_expr = args.next();
        } else if (mem.eql(u8, arg, "-r") or mem.eql(u8, arg, "--repl")) {
            repl.main(allocator, stdout, stdin, stderr) catch |err| {
                try stderr.print(
                    "Unhandled runtime error in REPL: {s}\n",
                    .{@errorName(err)},
                );
                return 1;
            };
            return 0;
        } else if (arg[0] == '-') {
            try usage(name);
            try stderr.print("error: unknown option '{s}'\n", .{arg});
            return 1;
        } else {
            options.input_filename = arg;
        }
    }

    const source = if (options.cl_expr) |cl_expr| cl_src: {
        options.extension = .blue;
        break :cl_src try allocator.dupe(u8, cl_expr);
    } else file_src: {
        const input_filename = options.input_filename orelse {
            try usage(name);
            try stderr.print("error: missing input file name\n", .{});
            return 1;
        };

        options.extension = getExtension(input_filename, &options.input_basename) orelse {
            try usage(name);
            try stderr.print("error: unrecognized file extension: {s}\n", .{input_filename});
            return 1;
        };

        var infile = fs.cwd().openFile(options.input_filename.?, .{}) catch |err| {
            try stderr.print(
                "error: unable to open input file {s}: {s}\n",
                .{ options.input_filename.?, @errorName(err) },
            );
            return 1;
        };
        defer infile.close();

        var reader = infile.reader();
        break :file_src reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
            try stderr.print(
                "error: unable to read file {s}: {s}\n",
                .{ input_filename, @errorName(err) },
            );
            return 1;
        };
    };

    defer allocator.free(source);

    var program: Program = undefined;

    switch (options.extension.?) {
        .vbf => {
            var binary_reader = io.fixedBufferStream(source);
            program = binary.load(binary_reader.reader(), allocator) catch |err| {
                try stderr.print(
                    "error: failed to read file {s}: {s}\n",
                    .{ options.input_filename.?, @errorName(err) },
                );
                return 1;
            };
        },
        .vmd => {
            var diagnostics = DiagnosticList.init(allocator, source);
            defer diagnostics.deinit();

            var assembler = Asm.init(source, allocator, &diagnostics);
            defer assembler.deinit();

            try assembler.assemble();

            if (diagnostics.hasDiagnosticsMinSeverity(.Error)) {
                try diagnostics.printAllDiagnostic(stderr);
                return 1;
            } else if (diagnostics.hasDiagnosticsMinSeverity(.Hint)) {
                try diagnostics.printAllDiagnostic(stdout);
            }

            const src_opts: Asm.EmbeddedSourceOptions = if (options.strip) .none else .vemod;
            program = try assembler.getProgram(allocator, src_opts);
        },
        .blue => {
            var diagnostics = DiagnosticList.init(allocator, source);
            defer diagnostics.deinit();

            var compilation = blue.compile(source, allocator, &diagnostics, false, null) catch {
                try diagnostics.printAllDiagnostic(stderr);
                return 1;
            };
            defer compilation.deinit();

            if (diagnostics.hasDiagnosticsMinSeverity(.Warning)) {
                try diagnostics.printAllDiagnostic(stdout);
            }

            if (options.output_asm) {
                const filename = options.output_filename orelse blk: {
                    try name_buffer.writer().writeAll(options.input_basename orelse "output");
                    try name_buffer.writer().writeAll(".vmd");
                    break :blk name_buffer.items;
                };
                var outfile = fs.cwd().createFile(filename, .{}) catch |err| {
                    try stderr.print(
                        "error: unable to create file {s}: {s}\n",
                        .{ filename, @errorName(err) },
                    );
                    return 1;
                };
                defer outfile.close();
                try outfile.writer().writeAll(compilation.result);
                return 0;
            }

            var assembler = Asm.init(compilation.result, allocator, &diagnostics);
            defer assembler.deinit();

            // reset diagnostics
            diagnostics.deinit();
            diagnostics = DiagnosticList.init(allocator, source);

            try assembler.assemble();

            if (diagnostics.hasDiagnosticsMinSeverity(.Error)) {
                try diagnostics.printAllDiagnostic(stderr);
                return 1;
            } else if (diagnostics.hasDiagnosticsMinSeverity(.Hint)) {
                try diagnostics.printAllDiagnostic(stdout);
            }

            const src_opts: Asm.EmbeddedSourceOptions = if (options.strip) .none else .{
                .frontend = .{
                    .tokens = compilation.tokens,
                    .source = source,
                },
            };
            program = try assembler.getProgram(allocator, src_opts);
        },
        .mcl => {
            try stderr.print("error: can't compile Melancolang yet\n", .{});
            return 1;
        },
    }

    defer program.deinit();

    switch (options.action) {
        .compile => {
            const output_filename = options.output_filename orelse blk: {
                try name_buffer.writer().writeAll(options.input_basename orelse "output");
                try name_buffer.writer().writeAll(".vbf");
                break :blk name_buffer.items;
            };
            var outfile = fs.cwd().createFile(output_filename, .{}) catch |err| {
                try stderr.print(
                    "error: unable to create file {s}: {s}\n",
                    .{ output_filename, @errorName(err) },
                );
                return 1;
            };
            defer outfile.close();

            binary.emit(outfile.writer(), program) catch |err| {
                try stderr.print(
                    "error: unable to emit binary: {s}\n",
                    .{@errorName(err)},
                );
                return 1;
            };
        },
        .run => {
            if (options.jit) {
                var jit = Jit.init(allocator);
                defer jit.deinit();

                var jit_fn = try jit.compile_program(program);
                defer jit_fn.deinit();

                const ret = jit_fn.execute() catch |err| {
                    if (jit_fn.rterror) |rterror| {
                        try print_rterror(program, rterror, stderr);
                    } else {
                        try stderr.print("error: {s}\n", .{@errorName(err)});
                    }
                    return 1;
                };
                return @intCast(ret);
            } else {
                var context = Context.init(program, allocator, &stdout, &stderr, false);
                defer context.deinit();
                const ret = interpreter.run(&context) catch |err| {
                    if (context.rterror) |rterror| {
                        try print_rterror(program, rterror, stderr);
                    } else {
                        try stderr.print("error: unknown runtime error {s}\n", .{@errorName(err)});
                    }
                    return 1;
                };
                return @intCast(ret);
            }
        },
    }

    return 0;
}
