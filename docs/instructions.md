# VeMod Instruction Reference

|Opcode|Mnemonic|Description|Long description|
|------|--------|-----------|----------------|
|00|**add**|Addition|Pops the top two elements from the stack and attempts to perform addition on them. Pushes the result to the stack on success. |
|01|**sub**|Subtraction|Pops the top two elements from the stack and attempts to perform subtraction on them. Pushes the result to the stack on success. The subtraction is performed with it's terms in the same order as they are pushed to the stack. |
|02|**mul**|Multiplication|Pops the top two elements from the stack and attempts to perform multiplication on them. Pushes the result to the stack on success. |
|03|**neg**|Arithmetic Negation|Negates the top value on the stack. |
|04|**div**|Division|Pops the top two elements from the stack and attempts to perform division on them. Pushes the result to the stack on success. The division is performed with it's terms in the same order as they are pushed to the stack. |
|05|**mod**|Modulus|Pops the top two elements from the stack and attempts to perform division on them. Pushes the remainder to the stack on success. The division is performed with it's terms in the same order as they are pushed to the stack. |
|06|**inc**|Increment|Increment an integer at the top of the stack. |
|07|**dec**|Decrement|Decrement an integer at the top of the stack. |
|08|**log_or**|Logical Disjunction|Pops the top two elements from the stack. Pushes 1 if either element is disjoint from zero |
|09|**log_and**|Logical Conjunction|Pops the top two elements from the stack. Pushes 1 if both elements are disjoint from zero |
|0A|**log_not**|Logical Negation|Negates the bits of the top value on the stack. |
|0B|**bit_or**|Binary Disjunction|Pops the top two elements from the stack. Performs a bitwise binary disjunction and pushes the result to the stack. |
|0C|**bit_xor**|Binary Exlusive Disjunction|Pops the top two elements from the stack. Performs a bitwise binary exclusive disjunction and pushes the result to the stack. |
|0D|**bit_and**|Binary Conjunction|Pops the top two elements from the stack. Performs a bitwise binary conjunction and pushes the result to the stack. |
|0E|**bit_not**|Binary Negation|Negates the bits of the top value on the stack. |
|0F|**cmp_lt**|Less than|Pops the top two elements from the stack and compares them. Pushes 1 if the second element to be popped is less than the first, pushes 0 otherwise. |
|10|**cmp_gt**|Greater than|Pops the top two elements from the stack and compares them. Pushes 1 if the second element to be popped is greater than the first, pushes 0 otherwise. |
|11|**cmp_le**|Less than or equal|Pops the top two elements from the stack and compares them. Pushes 1 if the second element to be popped is less than or equal to the first, pushes 0 otherwise. |
|12|**cmp_ge**|Greater than or equal|Pops the top two elements from the stack and compares them. Pushes 1 if the second element to be popped is greater than or equal to the first, pushes 0 otherwise. |
|13|**cmp_eq**|Equal|Pops the top two elements from the stack and compares them for equality. Pushes 1 if they are equal, 0 otherwise. |
|14|**cmp_ne**|Equal|Pops the top two elements from the stack and compares them for equality. Pushes 1 if they are not equal, 0 otherwise. |
|15|**jmp** *OP*|Unconditional jump|Jumps unconditionally to the label supplied as its operand. |
|16|**jmpnz** *OP*|Conditional jump|Pops the top element the stack, jumps to the label supplied as operand if and only if the popped element is non-zero. |
|17|**push** *OP*|Push integer|Push the integer literal supplied as its operand to the stack. |
|18|**pushf** *OP*|Push float|Push the float literal supplied as its operand to the stack. |
|19|**pushs** *OP*|Push string constant|Push the string constant supplied as operand to the stack. |
|1A|**pop**|Pop|Pop the top element of the stack and discard it. |
|1B|**dup**|Duplicate|Duplicates the top element of the stack. Does not copy reference types. |
|1C|**load** *OP*|Load local variable/parameter|Loads the local variable/parameter at the offset supplied as its operand, and pushes it to the stack. The offset is relative to the base pointer. |
|1D|**store** *OP*|Store local variable/parameter|Stores a value to the local variable/parameter at the offset supplied as its operand. The offset is relative to the base pointer. The value is popped from the stack before storing. |
|1E|**syscall** *OP*|Perform syscall|Performs a syscall with number supplied as its operand. Currently supported syscalls are: * %0: pop and print |
|1F|**call** *OP*|Call function|Calls the function with identifier supplied as its operand. |
|20|**ret**|Return from function|Pops the return value from stack and returns from the current function. Any passed arguments are popped from the stack and the return value is pushed. |
|21|**stack_alloc** *OP*|Stack allocation|Allocates N slots on the stack, where N is the integer literal supplied as operand, and initializes them all as Unit. |
|22|**struct_alloc**|Struct creation|Creates an empty struct and pushes a reference to it to the stack. |
|23|**struct_load** *OP*|Load struct field|Pops a struct reference from the stack. Tries to access the field with identifier supplied as operand and push it to the stack. If the field has not yet been initialized, pushes a Unit object. |
|24|**struct_store** *OP*|Store struct field|Pops a struct reference and a value from the stack. Stores the value at field with identifier supplied as operand in popped struct. |
|25|**list_alloc**|List creation|Creates an empty list and pushes a reference to it to the stack. |
|26|**list_load**|Load list element|Pops a list reference L and an index I from the stack, and pushes the element at index I in L. |
|27|**list_store**|Store list element|Pops a list reference L, an index I and a value V, and assigns V to the element at index I in L. |
|28|**list_length**|Get list length|Pops a list reference from the stack and pushes it's number of elements. |
|29|**list_append**|Append list element|Pops a list reference L and a value V from the stack, an appends V to the end of L. |
|2A|**list_pop**|Pop last element of list|Pops a list reference L, removes its last element and pushes it to the stack. |
|2B|**list_remove**|Remove list element|Pops an index I and a list reference L from the stack, and removes the element in L with index I. |
|2C|**list_concat**|Concatenate lists|Pops two lists references from the stack and appends the latter one to the former. |
|2D|**glob_store** *OP*|Store global variable|Pop a value from the stack and store it in the global variable with identifier supplied as operand. |
|2E|**glob_load** *OP*|Load global variable|Push the global variable with identifier supplied as operand to the stack. |
|2F|**deep_copy**|Deeply copy lists and objects|Pops the top element of the stack, and creates a new identical list/object. Also recursively recreates any contained lists/objects. For shallow copying use `dup`. |
