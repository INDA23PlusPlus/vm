const std = @import("std");

pub fn encode(writer: anytype, value: i64) void {
    std.leb.writeILEB128(writer, value);
}

pub fn decode(reader: anytype) !i64 {
    return std.leb.readILEB128(i64, reader);
}
