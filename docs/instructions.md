# VeMod Instruction Reference
## `add`
Pops the top two elements from the stack and attempts to perform addition on them.
Pushes the result to the stack on success.

## `sub`
Pops the top two elements from the stack and attempts to perform subtraction on them.
Pushes the result to the stack on success.
The subtraction is performed with it's terms in the same order as they are pushed
to the stack.

## `mul`
Pops the top two elements from the stack and attempts to perform multiplication on them.
Pushes the result to the stack on success.

## `neg`
Negates the top value on the stack.

## `div`
Pops the top two elements from the stack and attempts to perform division on them.
Pushes the result to the stack on success.
The division is performed with it's terms in the same order as they are pushed
to the stack.

## `mod`
Pops the top two elements from the stack and attempts to perform division on them.
Pushes the remainder to the stack on success.
The division is performed with it's terms in the same order as they are pushed
to the stack.

## `inc`

## `dec`

## `log_or`
Pops the top two elements from the stack.
Pushes 1 if either element is disjoint from zero

## `log_and`
Pops the top two elements from the stack.
Pushes 1 if both elements are disjoint from zero

## `log_not`
Negates the bits of the top value on the stack.

## `bit_or`
Pops the top two elements from the stack.
Performs a bitwise binary disjunction and pushes the result to the stack.

## `bit_xor`
Pops the top two elements from the stack.
Performs a bitwise binary exclusive disjunction and pushes the result to the stack.

## `bit_and`
Pops the top two elements from the stack.
Performs a bitwise binary conjunction and pushes the result to the stack.

## `bit_not`
Negates the bits of the top value on the stack.

## `cmp_lt`
Pops the top two elements from the stack and compares them.
Pushes 1 if the second element to be popped is less than the
first, pushes 0 otherwise.

## `cmp_gt`
Pops the top two elements from the stack and compares them.
Pushes 1 if the second element to be popped is greater than the
first, pushes 0 otherwise.

## `cmp_le`
Pops the top two elements from the stack and compares them.
Pushes 1 if the second element to be popped is less than or equal to the
first, pushes 0 otherwise.

## `cmp_ge`
Pops the top two elements from the stack and compares them.
Pushes 1 if the second element to be popped is greater than or equal to the
first, pushes 0 otherwise.

## `cmp_eq`
Pops the top two elements from the stack and compares them for equality.
Pushes 1 if they are equal, 0 otherwise.

## `cmp_ne`
Pops the top two elements from the stack and compares them for equality.
Pushes 1 if they are not equal, 0 otherwise.

## `jmp`
Jumps unconditionally to the label supplied as its operand.

## `jmpnz`
Pops the top element the stack, jumps to the label supplied as operand if and
only if the popped element is non-zero.

## `push`
Push the integer literal supplied as its operand to the stack.

## `pushf`
Push the float literal supplied as its operand to the stack.

## `pushs`

## `pop`
Pop the top element of the stack and discard it.

## `dup`
Duplicates the top element of the stack. Does not copy reference types.

## `load`
Loads the local variable/parameter at the offset supplied as its operand,
and pushes it to the stack.
The offset is relative to the base pointer.

## `store`
Stores a value to the local variable/parameter at the offset supplied as its operand.
The offset is relative to the base pointer. The value is popped from the stack before
storing.

## `syscall`
Performs a syscall with number supplied as its operand.
Currently supported syscalls are:
* %0: pop and print

## `call`
Calls the function with identifier supplied as its operand.

## `ret`
Pops the return value from stack and returns from the current function.
Any passed arguments are popped from the stack and the return value is
pushed.

## `stack_alloc`
Allocates N slots on the stack, where N is the integer literal supplied as operand,
and initializes them all as Unit.

## `struct_alloc`
Creates an empty struct and pushes a reference to it to the stack.

## `struct_load`
Pops a struct reference from the stack. Tries to access the field with identifier
supplied as operand and push it to the stack. If the field has not yet been initialized,
pushes a Unit object.

## `struct_store`
Pops a struct reference and a value from the stack. Stores the value at field with identifier
supplied as operand in popped struct.

## `list_alloc`
Creates an empty list and pushes a reference to it to the stack.

## `list_load`
Pops a list reference L and an index I from the stack, and pushes the element
at index I in L.

## `list_store`
Pops a list reference L, an index I and a value V, and assigns V to
the element at index I in L.

## `list_length`
Pops a list reference from the stack and pushes it's number of elements.

## `list_append`
Pops a list reference L and a value V from the stack, an appendsV to the
end of L.

## `list_pop`

## `list_remove`

## `list_concat`
Pops two lists references from the stack and appends the latter one to
the former.

