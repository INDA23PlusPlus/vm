const std = @import("std");
const builtin = @import("builtin");

const expected_zig_version_string = "0.12.0";

comptime {
    if (!std.mem.eql(u8, expected_zig_version_string, builtin.zig_version_string)) {
        @compileError("Wrong zig version " ++ builtin.zig_version_string ++ ", use " ++ expected_zig_version_string);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Arch
    //
    const arch_mod = b.addModule(
        "arch",
        .{ .root_source_file = .{ .path = "src/arch/module.zig" } },
    );

    const arch_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/arch/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const arch_run_tests = b.addRunArtifact(arch_tests);

    //
    // Assembler
    //
    const assembler_mod = b.addModule(
        "assembler",
        .{ .root_source_file = .{ .path = "src/asm/module.zig" } },
    );

    const assembler_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/asm/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const assembler_run_tests = b.addRunArtifact(assembler_tests);

    //
    // Memory manager
    //
    const memory_manager_mod = b.addModule(
        "memory_manager",
        .{ .root_source_file = .{ .path = "src/memory_manager/module.zig" } },
    );

    const memory_manager_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/memory_manager/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const memory_manager_run_tests = b.addRunArtifact(memory_manager_tests);

    //
    // VM
    //
    const vm_mod = b.addModule(
        "vm",
        .{ .root_source_file = .{ .path = "src/vm/module.zig" } },
    );

    const vm_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/vm/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const vm_run_tests = b.addRunArtifact(vm_tests);

    //
    // Compiler
    //
    const compiler_mod = b.addModule(
        "compiler",
        .{ .root_source_file = .{ .path = "src/compiler/module.zig" } },
    );

    const compiler_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/compiler/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const compiler_run_tests = b.addRunArtifact(compiler_tests);

    //
    // Language server
    //
    const vmdls_mod = b.addModule(
        "vmdls",
        .{ .root_source_file = .{ .path = "src/vmdls/module.zig" } },
    );

    const vmdls = b.addExecutable(.{
        .name = "vmdls",
        .root_source_file = .{ .path = "src/vmdls/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vmdls_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/vmdls/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const vmdls_run_tests = b.addRunArtifact(vmdls_tests);

    const build_vmdls = b.step("vmdls", "Build the VeMod language server");
    const install_vmdls = b.addInstallArtifact(vmdls, .{});
    build_vmdls.dependOn(&install_vmdls.step);

    //
    // Binary format deserializer & serializer.
    //
    const binary_mod = b.addModule(
        "binary",
        .{ .root_source_file = .{ .path = "src/binary/module.zig" } },
    );
    const binary_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/binary/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const binary_run_tests = b.addRunArtifact(binary_tests);

    //
    // Blue language
    //
    const blue_mod = b.addModule(
        "blue",
        .{ .root_source_file = .{ .path = "src/blue/module.zig" } },
    );
    const blue_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/blue/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const blue_run_tests = b.addRunArtifact(blue_tests);

    //
    // JIT
    //
    const jit_mod = b.addModule(
        "jit",
        .{ .root_source_file = .{ .path = "src/jit/module.zig" } },
    );
    const jit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/jit/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const jit_run_tests = b.addRunArtifact(jit_tests);

    //
    // Main executable
    //
    const vemod = b.addExecutable(.{
        .name = "vemod",
        .root_source_file = .{ .path = "src/vemod/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const build_vemod = b.step("vemod", "Build the main VeMod executable");
    const install_vemod = b.addInstallArtifact(vemod, .{});
    build_vemod.dependOn(&install_vemod.step);

    //
    // Executable dependencies
    //
    vmdls.root_module.addImport("compiler", compiler_mod);
    vmdls.root_module.addImport("asm", assembler_mod);
    vmdls.root_module.addImport("arch", arch_mod);
    vmdls.root_module.addImport("blue", blue_mod);
    vemod.root_module.addImport("arch", arch_mod);
    vemod.root_module.addImport("vm", vm_mod);
    vemod.root_module.addImport("asm", assembler_mod);
    vemod.root_module.addImport("binary", binary_mod);
    vemod.root_module.addImport("blue", blue_mod);
    vemod.root_module.addImport("jit", jit_mod);

    //
    // Module-module dependencies
    //
    vm_mod.addImport("arch", arch_mod);
    vm_mod.addImport("memory_manager", memory_manager_mod);
    vm_mod.addImport("asm", assembler_mod);
    assembler_mod.addImport("vm", vm_mod);
    assembler_mod.addImport("arch", arch_mod);
    binary_mod.addImport("arch", arch_mod);
    blue_mod.addImport("asm", assembler_mod);
    blue_mod.addImport("arch", arch_mod);
    jit_mod.addImport("arch", arch_mod);

    //
    // Test dependencies
    //
    assembler_tests.root_module.addImport("arch", arch_mod);
    assembler_tests.root_module.addImport("vm", vm_mod);
    vm_tests.root_module.addImport("arch", arch_mod);
    vm_tests.root_module.addImport("memory_manager", memory_manager_mod);
    vm_tests.root_module.addImport("asm", assembler_mod);
    binary_tests.root_module.addImport("arch", arch_mod);
    binary_tests.root_module.addImport("asm", assembler_mod);
    binary_tests.root_module.addImport("vm", vm_mod);
    blue_tests.root_module.addImport("arch", arch_mod);
    blue_tests.root_module.addImport("asm", assembler_mod);

    //
    // Unused modules
    //
    _ = .{ compiler_mod, vmdls_mod, binary_mod };

    //
    // Default build step
    //
    b.installArtifact(vmdls);
    b.installArtifact(vemod);

    //
    // Test step
    //
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&arch_run_tests.step);
    test_step.dependOn(&assembler_run_tests.step);
    test_step.dependOn(&compiler_run_tests.step);
    test_step.dependOn(&memory_manager_run_tests.step);
    test_step.dependOn(&vm_run_tests.step);
    test_step.dependOn(&vmdls_run_tests.step);
    test_step.dependOn(&binary_run_tests.step);
    test_step.dependOn(&blue_run_tests.step);
    test_step.dependOn(&jit_run_tests.step);

    //
    // Run step for compiler driver
    //
    const run_cmd = b.addRunArtifact(vemod);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run compiler driver");
    run_step.dependOn(&run_cmd.step);
}
