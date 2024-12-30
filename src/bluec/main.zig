//!
//! Blue native compiler
//!

const blue = @import("blue");
const diagnostic = @import("diagnostic");
const std = @import("std");
const builtin = @import("builtin");
const CodeGen = @import("CodeGen.zig");

const QbeTarget = enum {
    amd64_sysv,
    amd64_apple,
    arm64,
    arm64_apple,
    rv64,
};

fn fatalError(comptime fmt: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer().print("\x1b[31merror\x1b[0m: " ++ fmt ++ "\n", args) catch {};
    std.process.exit(1);
}

fn usage(me: []const u8, f: std.fs.File) void {
    f.writer().print(
        \\usage: {s} [options] [file]
        \\    -h            print this help message
        \\    -t <target>   specify target 
        \\    -c            only compile to QBE SSA
        \\    -o <output>   specify output file
        \\    -Wl,<options> pass comma separated options to the linker
        \\
    , .{me}) catch {};
    f.writer().print("supported targets are: ", .{}) catch {};
    inline for (std.meta.fields(QbeTarget), 0..) |target, i| {
        f.writer().print("{s}{s}", .{
            target.name,
            if (i < std.meta.fields(QbeTarget).len - 1) ", " else "\n",
        }) catch {};
    }
}

fn getCC(allocator: std.mem.Allocator) ![]const u8 {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    return allocator.dupe(u8, env.get("CC") orelse "cc");
}

fn stripExtension(path: []const u8) []const u8 {
    var index = path.len - 1;
    for (1..path.len) |i| {
        if (path[i] == '.') {
            index = i;
            break;
        }
    }
    return path[0..index];
}

fn concat(
    str1: []const u8,
    str2: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const len = str1.len + str2.len;
    const str = try allocator.alloc(u8, len);
    std.mem.copyForwards(u8, str[0..str1.len], str1);
    std.mem.copyForwards(u8, str[str1.len..], str2);
    return str;
}

fn run(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |c| {
            if (c == 0) return;
        },
        else => return,
    }

    try std.io.getStdErr().writeAll(result.stderr);
    fatalError("{s} failed", .{argv[0]});
}

pub fn main() !void {
    var args = std.process.args();
    const me = args.next().?;

    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    var only_compile = false;
    var ld_opts_str: []const u8 = "";
    var input = std.io.getStdIn();
    var basename: []const u8 = "";

    defer {
        if (input.handle != std.io.getStdIn().handle) {
            input.close();
        }
    }

    const arch = builtin.cpu.arch;
    var target: QbeTarget = switch (arch) {
        .x86_64 => .amd64_sysv,
        .aarch64 => .arm64,
        .riscv64 => .rv64,
        else => {
            usage(me, stderr);
            fatalError("unsupported native architecture: {s}", .{@tagName(arch)});
        },
    };

    while (args.next()) |arg_| {
        var arg = arg_;

        if (std.mem.startsWith(u8, arg, "-o")) {
            arg = arg[2..];
            if (arg.len == 0) {
                arg = args.next() orelse {
                    usage(me, stderr);
                    fatalError("missing option argument", .{});
                };
            }
            basename = arg;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-t")) {
            arg = arg[2..];
            if (arg.len == 0) {
                arg = args.next() orelse {
                    usage(me, stderr);
                    fatalError("missing option argument", .{});
                };
            }
            target = std.meta.stringToEnum(QbeTarget, arg) orelse {
                usage(me, stderr);
                fatalError("unsupported architecture: {s}", .{arg});
            };
            continue;
        }

        if (std.mem.eql(u8, arg, "-h")) {
            usage(me, stdout);
            std.process.exit(0);
        }

        if (std.mem.eql(u8, arg, "-c")) {
            only_compile = true;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-Wl,")) {
            ld_opts_str = arg;
            continue;
        }

        if (arg.len > 0 and arg[0] == '-') {
            usage(me, stderr);
            fatalError("invalid option {s}", .{arg});
        }

        input = std.fs.cwd().openFile(arg, .{}) catch |e| {
            fatalError("unable to open file {s}: {s}", .{ arg, @errorName(e) });
        };
        if (basename.len == 0) {
            basename = stripExtension(arg);
        }
    }

    if (basename.len == 0) {
        basename = "output";
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ssa_path = try concat(basename, ".ssa", allocator);
    const asm_path = try concat(basename, ".S", allocator);
    const obj_path = try concat(basename, ".o", allocator);
    defer allocator.free(ssa_path);
    defer allocator.free(asm_path);
    defer allocator.free(obj_path);
    const exe_path = basename;

    const source = input.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch |e| {
        fatalError("while reading input: {s}", .{@errorName(e)});
    };
    defer allocator.free(source);

    var diagnostics = diagnostic.DiagnosticList.init(allocator, source);
    defer diagnostics.deinit();

    var blue_compilation = blue.compile(source, allocator, &diagnostics, true, null) catch |e| {
        if (e == error.CompilationError) {
            try diagnostics.printAllDiagnostic(stderr.writer());
            fatalError("compilation failed", .{});
        }
        fatalError("{s}", .{@errorName(e)});
    };
    defer blue_compilation.deinit();

    {
        const ssa_file = std.fs.cwd().createFile(ssa_path, .{}) catch |e| {
            fatalError("unable to create {s}: {s}", .{ ssa_path, @errorName(e) });
        };
        defer ssa_file.close();

        const ast = &blue_compilation._ast;
        var codegen = CodeGen.init(ast, ssa_file, allocator);
        defer codegen.deinit();
        try codegen.run();
    }

    if (!only_compile) {
        const cc_cmd = try getCC(allocator);
        defer allocator.free(cc_cmd);

        var cc_argv = std.ArrayList([]const u8).init(allocator);
        defer cc_argv.deinit();

        try cc_argv.appendSlice(&.{ cc_cmd, "-lvemod", "-lc", "-o", exe_path, asm_path });

        if (ld_opts_str.len > 0) {
            try cc_argv.append(ld_opts_str);
        }

        try run(allocator, &.{ "qbe", "-t", @tagName(target), "-o", asm_path, ssa_path });
        try run(allocator, cc_argv.items);
    }

    std.process.exit(0);
}
