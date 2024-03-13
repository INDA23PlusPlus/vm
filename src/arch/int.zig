//!
//! Encoding / decoding of bytecode immediate values
//!
const std = @import("std");

/// ILEB128 encoding
pub fn encodeILEB128(writer: anytype, value: i64) !void {
    try std.leb.writeILEB128(writer, value);
}

/// ILEB128 decoding
pub fn decodeILEB128(reader: anytype) !i64 {
    return std.leb.readILEB128(i64, reader);
}

/// u64 address encoding
pub fn encodeAddress(ptr: *[8]u8, address: usize) void {
    std.mem.writeIntLittle(u64, ptr, address);
}

/// u64 address decoding
pub fn decodeAddress(ptr: *[8]u8) usize {
    return std.mem.readIntLittle(u64, ptr);
}
