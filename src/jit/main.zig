const std = @import("std");
const arch = @import("arch");
const vmd_asm_mod = @import("asm");
const Jit = @import("Jit.zig");

fn get_program(alloc: std.mem.Allocator) !arch.Program {
    var errors = std.ArrayList(vmd_asm_mod.Error).init(alloc);
    defer errors.deinit();

    const source =
        \\-function $main
        \\-begin
        \\    push    %37             # push n
        \\    push    %1              # one arg
        \\    call    $fib            # call fib(n)
        \\    ret                     # return result
        \\-end
        \\
        \\-function $fib
        \\-begin
        \\    load    %-4             # load n
        \\    push    %2              # push 2
        \\    cmp_lt                  # n < 2 ?
        \\    jmpnz   .less_than_two  # if true skip next block
        \\
        \\    load    %-4             # load n
        \\    push    %1              # push 1
        \\    sub                     # n - 1
        \\    push    %1              # one arg
        \\    call    $fib            # fib(n - 1)
        \\    load    %-4             # load n
        \\    push    %2              # push 2
        \\    sub                     # n - 2
        \\    push    %1              # one arg
        \\    call    $fib            # fib(n - 2)
        \\    add                     # sum fib(n - 1) + fib(n - 2)
        \\    ret                     # return sum
        \\
        \\.less_than_two
        \\    load    %-4             # load n
        \\    ret                     # return n
        \\-end
    ;

    var vmd_asm = vmd_asm_mod.Asm.init(source, alloc, &errors);
    defer vmd_asm.deinit();

    try vmd_asm.assemble();
    try std.testing.expectEqual(errors.items.len, 0);

    return try vmd_asm.getProgram(alloc, .none);
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var jit = Jit.init(gpa.allocator());
    defer jit.deinit();

    var prog = try get_program(gpa.allocator());
    defer prog.deinit();

    try jit.compile(prog);

    std.debug.print("{}\n", .{try jit.execute()});

    return 0;
}
