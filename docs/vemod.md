# The VeMod assembly language

## Basic types
VeMod is dynamically typed and garbage collected.
The basic types are unit, integers, strings, floats, lists and structs.
Lists can contain different types of objects.
Struct fields are created dynamically, with the 
`struct_store` instructions. Unit, integers and floats are value types,
while strings, lists and structs are reference types.

## Syntax
Valid tokens in VeMod assembly are:
| Token | Prefix | Example |
|-------|--------|---------|
| Keyword     | -    | -function |
| Instruction | none | push      |
| Identifier  | $    | $main     |
| String      | none | "hello"   |
| Label       | .    | .loop     |
| Integer     | %    | %42       |
| Float       | @    | @3.14     |

A VeMod program consists of function definitions and string constants.
The syntax for a string constant is
```
-string $name "content"
```

If multiple strings are provided following the string identifier,
they are concatenated together (as in C). A multi line string can thus 
be written as such:
```
-string $multiline-string
    "This is the first line\n"
    "This is the second line\n"
```

The syntax for function definitions is
```
-function $name
-begin
    ...instructions...
-end
```

## Stack layout and calling convention
Functions are called by pushing it's arguments, in order, followed by the number
of arguments and the `call` instruction. For example, calling a function with
two parameters can be done like this:
```
    push %1
    pushf @1.7
    push %2
    call $func
```

Parameter and local variables are accessed by an offset with the
current call frames base pointer, using the instructions `load` and
`store`. Local variables are indexed starting from 0. Loading the 
first local variable is done with `load %0`, etc.

Note that local variables must be allocated at the beginning of a function
with the `stack_alloc` instruction, which takes a number of objects to be allocated.


Arguments are placed 3 slots below the base pointer. For example, if a function
takes 2 parameters, argument 1 and 2 are accessed with `load %-5` and 
`load %-4` respectively.


## Control flow
Control flow is handled with labels and jump instructions.
The following code compares two local variables, and jumps
to a specified label if they are equal:
```
load %0
load %1
cmp_eq
jmpnz .label
````

## Instruction reference
### Arithmetic
| Syntax | Description |
|------|-------------|
| add | [ ..., A, B ] -> [ ..., A + B] |
| sub | [ ..., A, B ] -> [ ..., A - B] |
| mul | [ ..., A, B ] -> [ ..., A * B] |
| div | [ ..., A, B ] -> [ ..., A / B] |
| mod | [ ..., A, B ] -> [ ..., A % B] |

### Comparison
All comparisons push 1 if the comparison is true, and 0 otherwise.
| Syntax | Description |
|------|-------------|
| cmp_lt | [ ..., A, B ] -> [ ..., A < B ] |
| cmp_gt | [ ..., A, B ] -> [ ..., A > B ] |
| cmp_le | [ ..., A, B ] -> [ ..., A <= B ] |
| cmp_ge | [ ..., A, B ] -> [ ..., A >= B ] |
| cmp_eq | [ ..., A, B ] -> [ ..., A == B ] |
| cmp_ne | [ ..., A, B ] -> [ ..., A != B ] |

### Control flow
| Syntax | Description |
|------|-------------|
| jmp .label | Unconditional jump to .label |
| jmpnz .label | Pops top element, jumps to .label if result is non-zero |

### Stack operations
| Syntax | Description |
|------|-------------|
| push %x | [ ... ] -> [ ..., %x ] |
| pushf @x | [ ... ] -> [ ..., @x ] |
| pushs $str | [ ... ] -> [ ..., $str ] |
| pop | [ ..., A ] -> [ ... ] |
| dup | [ ..., A ] -> [ ..., A, A ] |
| stack_alloc %n | Pushes %n unit objects to the stack |

### List and struct operations
| Syntax | Description |
|--------|-------------|
| struct_alloc | Creates an empty struct and pushes it to the stack |
| struct_load $field | [ ..., S ] -> [ ... ] Pops S and pushes the value of $field in S, or unit if it doesn't exits. |
| struct_store $field | [ ..., S, V ] -> [ ... ] | Inserts/updates $field in struct S with value V. |
| list_alloc | Creates an empty list and pushes it to the stack |
| list_store | [ ..., L, I, V ] -> [ ..., L ] Stores value V at index I in list L |
| list_load | [ ..., L, I ] -> [ ..., L, V ] Pushes value at index I of list L |

### Misc.
| Syntax | Description |
|--------|-------------|
| syscall %0 | Performs a "syscall", such as printing |
| call $func | Pops arguments from stack and jumps to function $func |
| ret | Pops return value from stack and returns from current function |

### Syscalls
| Number | Description |
|--------|-------------|
| 0 | Pops an object from the stack and prints it |
