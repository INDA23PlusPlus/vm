# VeMod Binary Format

## Basic types
* ILEB128 - Little endian base 128 signed integer. 
* ULEB128 - Little endian base 128 unsigned integer.
* u64 - 64-bit little endian unsigned integer. 
* FourCC - Four byte ASCII character code.
* u8 - 1 byte.
* []u8 - An array of bytes.
* f64 - Little endian IEEE-754-2008 binary64 floating point numer.

## File structure
| Item | Type | Description |
|------|------|-------------|
| File identifier | FourCC | The ASCII characters 'VeMd' |
| String table size | u64 | The size of the string table in number of entries |
| String data size | u64 | The size of the string data section in bytes |
| Field table size | u64 | The size of the field table in number of entries |
| Field data size | u64 | The size of the field data section in bytes |
| Source table size | u64 | The size of the source table in number of entries |
| Source data size | u64 | The size of the source data section in bytes |
| Code size | u64 | The size of the code section in number of instructions |
| Global count | u64 | Number of global variables |
| Entry point | u64 | The address of the first instruction of the main function |
| String data | []u8 ||
| String table | See [Table format](#Table-format) ||
| Field data | []u8 ||
| Field table | See [Table format](#Table-format) ||
| Source data | []u8 ||
| Source table (tokens) | See [Table format](#Table-format) ||
| Code section | See [Code format](#Code-format) ||

## Table format
String and field tables consists of arrays of table entries.
Table entries consist of two 64-bit little endian unsigned integers, 
pointing to the start and end of the corresponding string in the
corresponding data section.

## Code format
The code section consists of a list of instructions. Each instruction
is a single byte for the opcode, followed by an optional ILEB128/ULEB128/float operand.
Floats are encoded as 64-bit IEEE-754-2008 floats, bitcast to little endian unsigned 64-bit integers.
The type of the operand is determined from the opcode. Unsigned values are used for
instructions which deal with addresses or string/field indices, while signed values are used
for instructions which deal with arithmetic, integer values and local variables.
Opcode values are hard coded in [opcode.zig](../arch/opcode.zig).
