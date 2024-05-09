//!
//! Runtime errors encapsulation and printing.
//!

const memman = @import("memory_manager");
const arch = @import("arch");
const VMContext = @import("VMContext.zig");
const Type = memman.APITypes.Type;
const Opcode = arch.Opcode;
const Instruction = arch.Instruction;
const SourceRef = @import("asm").SourceRef;

pub noinline fn printErr(ctxt: *const VMContext, comptime fmt: []const u8, args: anytype) !void {
    @setCold(true);
    const w = ctxt.errWriter();

    if (ctxt.prog.tokens == null) {
        try w.print("Runtime error: " ++ fmt, args);
        return;
    }

    const instr_addr = ctxt.pc - 1;
    const source = ctxt.prog.deinit_data.?.source.?;
    const token = ctxt.prog.tokens.?[instr_addr];
    const ref = try SourceRef.init(source, token);

    try w.print("Runtime error (line {d}): ", .{ref.line_num});
    try w.print(fmt, args);
    try ref.print(w);
}

pub const RtError = union(enum) {
    /// Invalid unary operator
    invalid_unop: struct {
        v: Type,
        op: Opcode,
    },
    /// Invalid binary operation
    invalid_binop: struct {
        l: Type,
        op: Opcode,
        r: Type,
    },
    /// Division by zero
    division_by_zero,
    /// A struct_store/load was performed on a non-struct type
    non_struct_field_access: Type,
    /// A list_store/load was performed on a non-list type
    non_list_indexing: Type,
    /// A list_store/load was performed with index being not of type int
    invalid_index_type: Type,
    /// Undefined syscall
    undefined_syscall: i64,
    /// The main function returned non-integer value
    non_int_main_ret_val: Type,

    pub fn print(rte: RtError, ctxt: *const VMContext) !void {
        switch (rte) {
            .division_by_zero => {
                try printErr(ctxt, "division by zero\n", .{});
            },
            .invalid_unop => |e| {
                const opstr = switch (e.op) {
                    .inc => "increment",
                    .dec => "decrement",
                    else => @tagName(e.op),
                };

                try printErr(
                    ctxt,
                    "can't perform {s} on type {s}\n",
                    .{ opstr, e.v.str() },
                );
            },
            .invalid_binop => |e| {
                const opstr = switch (e.op) {
                    .add => "addition",
                    .sub => "subtraction",
                    .mul => "multiplication",
                    .div, .mod => "division",
                    .cmp_lt,
                    .cmp_le,
                    .cmp_ge,
                    .cmp_gt,
                    => "comparison",
                    .cmp_eq, .cmp_ne => "equality check",
                    .list_concat => "concatenation",
                    else => @tagName(e.op),
                };

                try printErr(
                    ctxt,
                    "can't perform {s} on types {s} and {s}\n",
                    .{ opstr, e.l.str(), e.r.str() },
                );
            },
            .non_struct_field_access => |e| {
                try printErr(
                    ctxt,
                    "can't perform field access on type {s}\n",
                    .{e.str()},
                );
            },
            .non_list_indexing => |e| {
                try printErr(
                    ctxt,
                    "can't index in to type {s}\n",
                    .{e.str()},
                );
            },
            .invalid_index_type => |e| {
                try printErr(
                    ctxt,
                    "can't index with type {s}\n",
                    .{e.str()},
                );
            },
            .undefined_syscall => |e| {
                try printErr(
                    ctxt,
                    "undefined syscall number {d}\n",
                    .{e},
                );
            },
            .non_int_main_ret_val => |e| {
                try printErr(
                    ctxt,
                    "main function return value is of non-integer type {s}\n",
                    .{e.str()},
                );
            },
        }
    }
};
