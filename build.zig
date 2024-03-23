const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arch_mod = b.addModule(
        "arch",
        .{ .source_file = .{ .path = "src/arch/module.zig" } },
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

    const memory_manager_mod = b.addModule(
        "memory_manager",
        .{ .source_file = .{ .path = "src/memory_manager/module.zig" } },
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
    assembler.addModule("arch", arch_mod);
    assembler.addModule("vm", vm_mod);
    vm.addModule("memory_manager", memory_manager_mod);
    vm.addModule("arch", arch_mod);
    // When subprojects depend on modules that depend on other modules,
    // we need to do this
    vm_mod.dependencies.put("arch", arch_mod) catch unreachable;

    _ = .{
        assembler_mod,
        vm_mod,
        compiler_mod,
        memory_manager_mod,
    };

    b.installArtifact(assembler);
    b.installArtifact(vm);
    b.installArtifact(compiler);

    const test_step = b.step("test", "Run unit tests");
    for ([_][]const u8{
        "src/arch/module.zig",
        "src/asm/module.zig",
        "src/compiler/module.zig",
        "src/memory_manager/module.zig",
        "src/vm/module.zig",
    }) |file| {
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = file },
            .target = target,
            .optimize = .Debug,
        });

        // TODO: kind of a bad way of doing this, maybe we should separate out all the different that have dependencies on other modules?
        unit_tests.addModule("asm", assembler_mod);
        unit_tests.addModule("arch", arch_mod);
        unit_tests.addModule("memory_manager", memory_manager_mod);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
