//!
//! Textual descriptions of instructions.
//!

const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;

pub const text = blk: {
    var arr = std.EnumArray(Opcode, []const u8).initUndefined();
    const Entry = struct { Opcode, []const u8 };
    const entries = [_]Entry{
        .{
            .add,
            \\# Addition
            \\
            \\Pops the top two elements from the stack and attempts to perform addition on them.
            \\Pushes the result to the stack on success.
            \\
            ,
        },
        .{
            .sub,
            \\# Subtraction
            \\
            \\Pops the top two elements from the stack and attempts to perform subtraction on them.
            \\Pushes the result to the stack on success.
            \\The subtraction is performed with it's terms in the same order as they are pushed
            \\to the stack.
            \\
            ,
        },
        .{
            .mul,
            \\# Multiplication
            \\
            \\Pops the top two elements from the stack and attempts to perform multiplication on them.
            \\Pushes the result to the stack on success.
            \\
            ,
        },
        .{
            .div,
            \\# Division
            \\
            \\Pops the top two elements from the stack and attempts to perform division on them.
            \\Pushes the result to the stack on success.
            \\The division is performed with it's terms in the same order as they are pushed
            \\to the stack.
            \\
            ,
        },
        .{
            .mod,
            \\# Modulus
            \\
            \\Pops the top two elements from the stack and attempts to perform division on them.
            \\Pushes the remainder to the stack on success.
            \\The division is performed with it's terms in the same order as they are pushed
            \\to the stack.
            \\
            ,
        },
        .{
            .cmp_lt,
            \\# Less than
            \\
            \\Pops the top two elements from the stack and compares them.
            \\Pushes 1 if the second element to be popped is less than the
            \\first, pushes 0 otherwise.
            \\
            ,
        },
        .{
            .cmp_gt,
            \\# Greater than
            \\
            \\Pops the top two elements from the stack and compares them.
            \\Pushes 1 if the second element to be popped is greater than the
            \\first, pushes 0 otherwise.
            \\
            ,
        },
        .{
            .cmp_le,
            \\# Less than or equal
            \\
            \\Pops the top two elements from the stack and compares them.
            \\Pushes 1 if the second element to be popped is less than or equal to the
            \\first, pushes 0 otherwise.
            \\
            ,
        },
        .{
            .cmp_ge,
            \\# Greater than or equal
            \\
            \\Pops the top two elements from the stack and compares them.
            \\Pushes 1 if the second element to be popped is greater than or equal to the
            \\first, pushes 0 otherwise.
            \\
            ,
        },
        .{
            .cmp_eq,
            \\# Equal
            \\
            \\Pops the top two elements from the stack and compares them for equality.
            \\Pushes 1 if they are equal, 0 otherwise.
            \\
            ,
        },
        .{
            .cmp_ne,
            \\# Equal
            \\
            \\Pops the top two elements from the stack and compares them for equality.
            \\Pushes 1 if they are not equal, 0 otherwise.
            \\
            ,
        },
        .{
            .jmp,
            \\# Unconditional jump
            \\
            \\Jumps unconditionally to the label supplied as its operand.
            \\
            ,
        },
        .{
            .jmpnz,
            \\# Conditional jump
            \\
            \\Pops the top element the stack, jumps to the label supplied as operand if and
            \\only if the popped element is non-zero.
            \\
            ,
        },
        .{
            .push,
            \\# Push integer
            \\
            \\Push the integer literal supplied as its operand to the stack.
            \\
            ,
        },
        .{
            .pushf,
            \\# Push float
            \\
            \\Push the float literal supplied as its operand to the stack.
            \\
            ,
        },
        .{
            .pop,
            \\# Pop
            \\
            \\Pop the top element of the stack and discard it.
            \\
            ,
        },
        .{
            .dup,
            \\# Duplicate
            \\
            \\Duplicates the top element of the stack. Does not copy reference types.
            \\
            ,
        },
        .{
            .load,
            \\# Load local variable/parameter
            \\
            \\Loads the local variable/parameter at the offset supplied as its operand,
            \\and pushes it to the stack.
            \\The offset is relative to the base pointer.
            \\
            ,
        },
        .{
            .store,
            \\# Store local variable/parameter
            \\
            \\Stores a value to the local variable/parameter at the offset supplied as its operand.
            \\The offset is relative to the base pointer. The value is popped from the stack before
            \\storing.
            \\
            ,
        },
        .{
            .syscall,
            \\# Perform syscall
            \\
            \\Performs a syscall with number supplied as its operand.
            \\Currently supported syscalls are:
            \\* %0: pop and print
            \\
            ,
        },
        .{
            .call,
            \\# Call function
            \\
            \\Calls the function with identifier supplied as its operand.
            \\
            ,
        },
        .{
            .ret,
            \\# Return from function
            \\
            \\Pops the return value from stack and returns from the current function.
            \\Any passed arguments are popped from the stack and the return value is
            \\pushed.
            \\
            ,
        },
        .{
            .stack_alloc,
            \\# Stack allocation
            \\
            \\Allocates N slots on the stack, where N is the integer literal supplied as operand,
            \\and initializes them all as Unit.
            \\
            ,
        },
        .{
            .struct_alloc,
            \\# Struct creation
            \\
            \\Creates an empty struct and pushes a reference to it to the stack.
            \\
            ,
        },
        .{
            .struct_load,
            \\# Load struct field
            \\
            \\Pops a struct reference from the stack. Tries to access the field with identifier
            \\supplied as operand and push it to the stack. If the field has not yet been initialized,
            \\pushes a Unit object.
            \\
            ,
        },
        .{
            .struct_store,
            \\# Store struct field
            \\
            \\Pops a struct reference and a value from the stack. Stores the value at field with identifier
            \\supplied as operand in popped struct.
            \\
            ,
        },
        .{
            .list_alloc,
            \\# List creation
            \\
            \\Creates an empty list and pushes a reference to it to the stack.
            \\
            ,
        },
        .{
            .list_load,
            \\# Load list element
            \\
            \\ TODO !!!
            \\
            ,
        },
        .{
            .list_store,
            \\# Store list element
            \\
            \\ TODO !!!
            \\
            ,
        },
    };

    for (entries) |entry| arr.set(entry.@"0", entry.@"1");
    break :blk arr;
};
