const Asm = @import("Asm.zig");

/// Emit bytecode from assembled program
pub fn emit(self: *Asm, writer: anytype) !void {
    _ = self;
    try writer.print("hello!", .{});
}
