//!
//! Runtime errors encapsulation and printing.
//!

const arch = @import("arch");
const RtError = arch.err.RtError;
const VMContext = @import("VMContext.zig");
const SourceRef = @import("asm").SourceRef;

pub noinline fn print(ctxt: *const VMContext, rte: RtError) !void {
    @setCold(true);
    const w = ctxt.errWriter();

    if (ctxt.prog.tokens == null) {
        _ = try w.write("Runtime error: ");
        try rte.err.print(w);
        return;
    }

    const source = ctxt.prog.deinit_data.?.source.?;
    const token = ctxt.prog.tokens.?[rte.pc];
    const ref = try SourceRef.init(source, token);

    try w.print("Runtime error (line {d}): ", .{ref.line_num});
    try rte.err.print(w);
    try ref.print(w);
}
