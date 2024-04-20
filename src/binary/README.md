# VeMod Binary Format

## Basic types
* ILEB128 - Little endian base 128 signed integer. 
* ULEB128 - Little endian base 128 unsigned integer.
* u64 - 64-bit little endian unsigned integer. 
* FourCC - Four byte ASCII character code.
* u8 - 1 byte.
* []u8 - An array of bytes.

## File structure
| Item | Type | Description |
|------|------|-------------|
| File identifier | FourCC | The ASCII characters 'VeMd' |
| String table size | u64 | The size of the string table in bytes |
| String data size | u64 | The size of the string data section in bytes |
| Field table size | u64 | The size of the field table in bytes |
| Field data size | u64 | The size of the field data section in bytes |
| Code size | u64 | The size of the code section in bytes |
| Entry point | u64 | The address of the first instruction of the main function |
| String table | See [Table format](#Table-format) ||
| String data | []u8 ||
| Field table | See [Table format](#Table-format) ||
| Field data | []u8 ||
| Code section | See [Code format](#Code-format) ||

## Table format
String and field tables consists of arrays of table entries.
Table entries consist of two 64-bit little endian unsigned integers, 
pointing to the start and end of the corresponding string in the
corresponding data section.

## Code format
The code section consists of a list of instructions. Each instruction
is a single byte for the opcode, followed by an optional ILEB128/ULEB128 operand.
The type of the operand is determined from the opcode. Unsigned values are used for
instructions which deal with addresses or string/field indices, while signed values are used
for instructions which deal with arithmetic, integer values and local variables.
Opcode values are hard coded in [opcode.zig](../arch/opcode.zig).
