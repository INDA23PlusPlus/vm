const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const instr_mod = b.addModule(
        "instr",
        .{ .root_source_file = .{ .path = "src/instr/module.zig" } },
    );

    const assembler_mod = b.addModule(
        "assembler",
        .{ .root_source_file = .{ .path = "src/asm/module.zig" } },
    );

    const assembler = b.addExecutable(.{
        .name = "asm",
        .root_source_file = .{ .path = "src/asm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vm_mod = b.addModule(
        "vm",
        .{ .root_source_file = .{ .path = "src/vm/module.zig" } },
    );

    const vm = b.addExecutable(.{
        .name = "vm",
        .root_source_file = .{ .path = "src/vm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const compiler_mod = b.addModule(
        "compiler",
        .{ .root_source_file = .{ .path = "src/compiler/module.zig" } },
    );

    const compiler = b.addExecutable(.{
        .name = "compiler",
        .root_source_file = .{ .path = "src/compiler/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(assembler);
    b.installArtifact(vm);
    b.installArtifact(compiler);

    // Subprojects can depend on modules like so:
    // assembler.root_module.addImport("instr", instr_mod);
    // ...and exposed objects are used like so:
    // const Instruction = @import("instr").Instruction;
    _ = .{
        instr_mod,
        assembler_mod,
        vm_mod,
        compiler_mod,
    };

    // TODO: Add tests
}
