//!
//! Main interpreter
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const Type = @import("types.zig").Type;
const VMInstruction = @import("VMInstruction.zig");

/// returns exit code of the program
pub fn run(code: []const VMInstruction, allocator: Allocator) !void {
    var ip: usize = 0;
    var stack = std.ArrayList(Type).init(allocator);
    while (ip < code.len) {
        const i = code[ip];
        switch (i.op) {
            .push => {
                try stack.append(Type.from(i.operand));
            },
            .pop => {
                const popped_val = stack.popOrNull() orelse return error.PoppedEmptyStack;
                std.debug.print("popped: {}\n", .{popped_val});
            },
            else => std.debug.panic("unimplemented instruction {}\n", .{i}),
        }
        if (i.op != .jmp and i.op != .jmpnz) {
            ip += 1;
        }
    }
}
