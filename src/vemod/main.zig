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

const asm_ = @import("asm");
const Asm = asm_.Asm;
const AsmError = asm_.Error;

const binary = @import("binary");

const vm = @import("vm");
const Context = vm.VMContext;
const interpreter = vm.interpreter;

const blue = @import("blue");

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

fn getExtension(filename: []const u8) ?Extension {
    if (filename.len == 0) return null;
    var iter = mem.tokenizeScalar(u8, filename, '.');
    var ext: []const u8 = undefined;
    while (iter.next()) |tok| ext = tok;
    return meta.stringToEnum(Extension, ext);
}

const Options = struct {
    action: enum { compile, run } = .run,
    output_filename: ?[]const u8 = null,
    input_filename: ?[]const u8 = null,
    extension: ?Extension = null,
    strip: bool = false,
};

fn usage(name: []const u8) !void {
    try io.getStdOut().writer().print(
        \\Usage:
        \\    {s} [-c | -h] INPUT [-o OUTPUT]
        \\
        \\Options:
        \\    -c          Only compile.
        \\    -o OUTPUT   Write output to file OUTPUT
        \\    -s          Don't include source information in compiled program.
        \\    -h          Show this help message and exit.
        \\
    , .{name});
}

pub fn main() !u8 {

    // Parse command line options
    var options = Options{};

    var args = process.args();
    const name = args.next().?;

    const stdout = io.getStdOut().writer();
    const stderr = io.getStdErr().writer();

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-c")) {
            options.action = .compile;
        } else if (mem.eql(u8, arg, "-o")) {
            options.output_filename = args.next() orelse {
                try stderr.print("error: missing output file name\n", .{});
                try usage(name);
                return 1;
            };
        } else if (mem.eql(u8, arg, "-h")) {
            try usage(name);
            return 0;
        } else if (mem.eql(u8, arg, "-s")) {
            options.strip = true;
        } else if (arg[0] == '-') {
            try stderr.print("error: unknown option '{s}'\n", .{arg});
            try usage(name);
            return 1;
        } else {
            options.input_filename = arg;
        }
    }

    const input_filename = options.input_filename orelse {
        try stderr.print("error: missing input file name\n", .{});
        try usage(name);
        return 1;
    };

    options.extension = getExtension(input_filename) orelse {
        try stderr.print("error: unrecognized file extension: {s}\n", .{input_filename});
        try usage(name);
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
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var program: Program = undefined;

    switch (options.extension.?) {
        .vbf => {
            program = binary.load(reader, allocator) catch |err| {
                try stderr.print(
                    "error: failed to read file {s}: {s}\n",
                    .{ input_filename, @errorName(err) },
                );
                return 1;
            };
        },
        .vmd => {
            const source = reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
                try stderr.print(
                    "error: unable to read file {s}: {s}\n",
                    .{ input_filename, @errorName(err) },
                );
                return 1;
            };
            defer allocator.free(source);

            var errors = ArrayList(AsmError).init(allocator);
            defer errors.deinit();

            var assembler = Asm.init(source, allocator, &errors);
            defer assembler.deinit();

            try assembler.assemble();

            if (errors.items.len > 0) {
                for (errors.items) |err| {
                    try err.print(source, stderr);
                }
                return 1;
            }

            const src_opts: Asm.EmbeddedSourceOptions = if (options.strip) .none else .vemod;
            program = try assembler.getProgram(allocator, src_opts);
        },
        .blue => {
            const source = reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
                try stderr.print(
                    "error: unable to read file {s}: {s}\n",
                    .{ input_filename, @errorName(err) },
                );
                return 1;
            };
            defer allocator.free(source);

            var errors = ArrayList(AsmError).init(allocator);
            defer errors.deinit();

            var lexer = blue.Token.Lexer.init(source, &errors);
            var ast = blue.Ast.init(allocator);
            defer ast.deinit();

            var parser = blue.Parser.init(&ast, &lexer, &errors);
            defer parser.deinit();

            try parser.parse();

            if (errors.items.len > 0) {
                for (errors.items) |err| {
                    try err.print(source, stderr);
                }
                return 1;
            }

            try ast.print(stdout);
            return 0;
        },
        .mcl => {
            try stderr.print("error: can't compile Melancolang yet\n", .{});
            return 1;
        },
    }

    defer program.deinit();

    switch (options.action) {
        .compile => {
            const output_filename = options.output_filename orelse "output.vbf";
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
            var context = Context.init(program, allocator, &stdout, &stderr, false);
            defer context.deinit();
            const ret = interpreter.run(&context) catch |err| {
                if (context.rterror) |rterror| {
                    try rterror.print(&context);
                } else {
                    try stderr.print("error: unknown runtime error {s}\n", .{@errorName(err)});
                }
                return 1;
            };
            return @intCast(ret);
        },
    }

    return 0;
}
