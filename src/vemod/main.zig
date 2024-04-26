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
const preproc = asm_.preproc;

const binary = @import("binary");

const vm = @import("vm");
const Context = vm.VMContext;
const interpreter = vm.interpreter;

const InputType = enum { vmd, mcl, vbf };

fn getInputType(filename: []const u8) ?InputType {
    var dot_id = filename.len - 1;
    if (filename[dot_id] == '.') return null;

    while (true) {
        if (filename[dot_id] == '.') break;
        if (dot_id == 0) return null;
        dot_id -= 1;
    }

    const ext = filename[dot_id + 1 ..];
    return meta.stringToEnum(InputType, ext);
}

const Options = struct {
    action: enum { compile, run } = .run,
    output: ?[]const u8 = null,
    input: ?[]const u8 = null,
    input_type: ?InputType = null,
};

fn usage(name: []const u8) !void {
    try io.getStdOut().writer().print(
        \\Usage:
        \\    {s} [-c | -h] INPUT [-o OUTPUT]
        \\
        \\Options:
        \\    -c          Only compile.
        \\    -o OUTPUT   Write output to file OUTPUT
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
            options.output = args.next() orelse {
                try stderr.print("error: missing output file name\n", .{});
                try usage(name);
                return 1;
            };
        } else if (mem.eql(u8, arg, "-h")) {
            try usage(name);
            return 0;
        } else {
            options.input = arg;
        }
    }

    if (options.input == null) {
        try stderr.print("error: missing input file name\n", .{});
        try usage(name);
        return 1;
    }

    options.input_type = getInputType(options.input.?) orelse {
        try stderr.print("error: unrecognized file extension: {s}\n", .{options.input.?});
        try usage(name);
        return 1;
    };

    var file = fs.cwd().openFile(options.input.?, .{}) catch |err| {
        try stderr.print(
            "error: unable to open input file {s}: {s}\n",
            .{ options.input.?, @errorName(err) },
        );
        return 1;
    };
    defer file.close();

    var reader = file.reader();
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    var program: Program = undefined;
    // make sure we don't free unitialized program
    program.deinit_data = null;
    defer program.deinit();

    switch (options.input_type.?) {
        .vbf => {
            program = binary.load(reader, allocator) catch |err| {
                try stderr.print(
                    "error: failed to read file {s}: {s}\n",
                    .{ options.input.?, @errorName(err) },
                );
                return 1;
            };
        },
        .vmd => {
            const source = reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
                try stderr.print(
                    "error: unable to read file {s}: {s}\n",
                    .{ options.input.?, @errorName(err) },
                );
                return 1;
            };
            defer allocator.free(source);

            const source_pp = try preproc.run(source, allocator);
            defer allocator.free(source_pp);

            var errors = ArrayList(AsmError).init(allocator);
            defer errors.deinit();

            var assembler = Asm.init(source_pp, allocator, &errors);
            defer assembler.deinit();

            try assembler.assemble();

            if (errors.items.len > 0) {
                for (errors.items) |err| {
                    try err.print(source_pp, stderr);
                }
                return 1;
            }

            program = try assembler.getProgram(allocator);
        },
        .mcl => {
            try stderr.print("error: can't compile Melancolang yet\n", .{});
            return 1;
        },
    }

    switch (options.action) {
        .compile => {
            const filename = options.output orelse "output.vbf";
            var outfile = fs.cwd().createFile(filename, .{}) catch |err| {
                try stderr.print(
                    "error: unable to create file {s}: {s}\n",
                    .{ filename, @errorName(err) },
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
            var context = Context.init(program, allocator, &stdout, false);
            defer context.deinit();
            const ret = interpreter.run(&context) catch |err| {
                try stderr.print(
                    "runtime error: {s}\n",
                    .{@errorName(err)},
                );
                return 1;
            };
            return @intCast(ret);
        },
    }

    return 0;
}
