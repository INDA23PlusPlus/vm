const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // Arch
    //
    const arch_mod = b.addModule(
        "arch",
        .{ .source_file = .{ .path = "src/arch/module.zig" } },
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
        .{ .source_file = .{ .path = "src/asm/module.zig" } },
    );

    const assembler = b.addExecutable(.{
        .name = "asm",
        .root_source_file = .{ .path = "src/asm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const assembler_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/asm/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const assembler_run_tests = b.addRunArtifact(assembler_tests);

    const build_assembler = b.step("asm", "Build the assembler");
    const install_assembler = b.addInstallArtifact(assembler, .{});
    build_assembler.dependOn(&install_assembler.step);

    //
    // Memory manager
    //
    const memory_manager_mod = b.addModule(
        "memory_manager",
        .{ .source_file = .{ .path = "src/memory_manager/module.zig" } },
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
        .{ .source_file = .{ .path = "src/vm/module.zig" } },
    );

    const vm = b.addExecutable(.{
        .name = "vm",
        .root_source_file = .{ .path = "src/vm/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vm_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/vm/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const vm_run_tests = b.addRunArtifact(vm_tests);

    const build_vm = b.step("vm", "Build the VM");
    const install_vm = b.addInstallArtifact(vm, .{});
    build_vm.dependOn(&install_vm.step);

    //
    // Compiler
    //
    const compiler_mod = b.addModule(
        "compiler",
        .{ .source_file = .{ .path = "src/compiler/module.zig" } },
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
    const langserver_mod = b.addModule(
        "langserver",
        .{ .source_file = .{ .path = "src/langserver/module.zig" } },
    );

    const langserver = b.addExecutable(.{
        .name = "mclls",
        .root_source_file = .{ .path = "src/langserver/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const langserver_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/langserver/module.zig" },
        .target = target,
        .optimize = optimize,
    });
    const langserver_run_tests = b.addRunArtifact(langserver_tests);

    const build_langserver = b.step("langserver", "Build the language server");
    const install_langserver = b.addInstallArtifact(langserver, .{});
    build_langserver.dependOn(&install_langserver.step);

    //
    // Executable dependencies
    //
    assembler.addModule("arch", arch_mod);
    assembler.addModule("vm", vm_mod);
    vm.addModule("memory_manager", memory_manager_mod);
    vm.addModule("arch", arch_mod);
    langserver.addModule("compiler", compiler_mod);
    langserver.addModule("asm", assembler_mod);
    langserver.addModule("arch", arch_mod);

    //
    // Module-module dependencies
    //
    vm_mod.dependencies.put("arch", arch_mod) catch unreachable;
    assembler_mod.dependencies.put("vm", vm_mod) catch unreachable;
    assembler_mod.dependencies.put("arch", arch_mod) catch unreachable;

    //
    // Test dependencies
    //
    assembler_tests.addModule("arch", arch_mod);
    assembler_tests.addModule("vm", vm_mod);
    vm_tests.addModule("arch", arch_mod);
    vm_tests.addModule("memory_manager", memory_manager_mod);

    //
    // Unused modules
    //
    _ = .{ compiler_mod, langserver_mod };

    //
    // Default build step
    //
    b.installArtifact(assembler);
    b.installArtifact(vm);
    b.installArtifact(langserver);

    //
    // Test step
    //
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&arch_run_tests.step);
    test_step.dependOn(&assembler_run_tests.step);
    test_step.dependOn(&compiler_run_tests.step);
    test_step.dependOn(&memory_manager_run_tests.step);
    test_step.dependOn(&vm_run_tests.step);
    test_step.dependOn(&langserver_run_tests.step);
}
