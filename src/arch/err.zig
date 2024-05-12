//!
//! Architectural runtime error definitions.
//!

const Type = @import("type.zig").Type;
const Opcode = @import("opcode.zig").Opcode;

pub const ErrorSpecifier = union(enum) {
    /// Invalid unary operator
    invalid_unop: struct {
        t: Type,
        op: Opcode,
    },
    /// Invalid binary operation
    invalid_binop: struct {
        lt: Type,
        op: Opcode,
        rt: Type,
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
    /// A list_length was performed on something else than a list
    non_list_length: Type,

    pub fn print(err: ErrorSpecifier, writer: anytype) !void {
        switch (err) {
            .division_by_zero => {
                try writer.print("division by zero\n", .{});
            },
            .invalid_unop => |e| {
                const opstr = switch (e.op) {
                    .inc => "increment",
                    .dec => "decrement",
                    else => @tagName(e.op),
                };

                try writer.print(
                    "can't perform {s} on type {s}\n",
                    .{ opstr, e.t.str() },
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

                try writer.print(
                    "can't perform {s} on types {s} and {s}\n",
                    .{ opstr, e.lt.str(), e.rt.str() },
                );
            },
            .non_struct_field_access => |e| {
                try writer.print(
                    "can't perform field access on type {s}\n",
                    .{e.str()},
                );
            },
            .non_list_indexing => |e| {
                try writer.print(
                    "can't index in to type {s}\n",
                    .{e.str()},
                );
            },
            .non_list_length => |e| {
                try writer.print(
                    "can't get length of non-list type {s}\n",
                    .{e.str()},
                );
            },
            .invalid_index_type => |e| {
                try writer.print(
                    "can't index with type {s}\n",
                    .{e.str()},
                );
            },
            .undefined_syscall => |e| {
                try writer.print(
                    "undefined syscall number {d}\n",
                    .{e},
                );
            },
            .non_int_main_ret_val => |e| {
                try writer.print(
                    "main function return value is of non-integer type {s}\n",
                    .{e.str()},
                );
            },
        }
    }
};

pub const RtError = struct {
    pc: ?usize,
    err: ErrorSpecifier,
};
