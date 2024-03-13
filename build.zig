const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const instr_mod = b.addModule(
        "instr",
        .{ .source_file = .{ .path = "src/instr/module.zig" } },
    );

    const assembler_mod = b.addModule(
        "assembler",
        .{ .source_file = .{ .path = "src/asm/module.zig" } },
    );

    const assembler = b.addExecutable(.{
        .name = "asm",
        .root_source_file = .{ .path = "src/asm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vm_mod = b.addModule(
        "vm",
        .{ .source_file = .{ .path = "src/vm/module.zig" } },
    );

    const vm = b.addExecutable(.{
        .name = "vm",
        .root_source_file = .{ .path = "src/vm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const compiler_mod = b.addModule(
        "compiler",
        .{ .source_file = .{ .path = "src/compiler/module.zig" } },
    );

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .root_source_file = .{ .path = "src/compiler/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Subprojects can depend on modules like so:
    //assembler.root_module.addImport("instr", instr_mod);
    assembler.addModule("instr", instr_mod);
    // ...and exposed objects are used like so:
    // const Instruction = @import("instr").Instruction;

    _ = .{
        assembler_mod,
        vm_mod,
        compiler_mod,
    };

    b.installArtifact(assembler);
    b.installArtifact(vm);
    b.installArtifact(compiler);

    // TODO: Add tests
}
