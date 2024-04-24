//!
//! Binary format serialization and deserialization.
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const meta = std.meta;
const leb = std.leb;
const arch = @import("arch");
const Program = arch.Program;
const Opcode = arch.Opcode;
const Instruction = arch.Instruction;

const Error = error{
    InvalidFileID,
    NonContigousDataSegments,
} || meta.IntToEnumError;

const Header = struct {
    string_table_size: u64,
    string_data_size: u64,
    field_table_size: u64,
    field_data_size: u64,
    code_size: u64,
    entry_point: u64,
};

const Table = struct {
    entries: []const []const u8,
    data: []const u8,
};

pub fn load(reader: anytype, allocator: Allocator) !Program {
    const header = try loadHeader(reader);

    const string_table = try loadTable(
        reader,
        header.string_table_size,
        header.string_data_size,
        allocator,
    );

    const field_table = try loadTable(
        reader,
        header.field_table_size,
        header.field_data_size,
        allocator,
    );

    var code = try allocator.alloc(Instruction, header.code_size);
    for (code) |*instruction| {
        instruction.* = try loadInstruction(reader);
    }

    return .{
        .code = code,
        .entry = header.entry_point,
        .strings = string_table.entries,
        .field_names = field_table.entries,
        .deinit_data = .{
            .allocator = allocator,
            .strings = string_table.data,
            .field_names = field_table.data,
        },
    };
}

pub fn emit(writer: anytype, program: Program) !void {
    const deinit_data = program.deinit_data orelse return Error.NonContigousDataSegments;

    const header = Header{
        .string_table_size = program.strings.len,
        .string_data_size = deinit_data.strings.len,
        .field_table_size = program.field_names.len,
        .field_data_size = deinit_data.field_names.len,
        .code_size = program.code.len,
        .entry_point = program.entry,
    };

    try emitHeader(writer, header);

    const string_table = Table{
        .entries = program.strings,
        .data = deinit_data.strings,
    };

    const field_table = Table{
        .entries = program.field_names,
        .data = deinit_data.field_names,
    };

    try emitTable(writer, string_table);
    try emitTable(writer, field_table);

    for (program.code) |instruction| {
        try emitInstruction(writer, instruction);
    }
}

fn loadHeader(reader: anytype) !Header {
    if (!(try reader.isBytes("VeMd"))) return Error.InvalidFileID;
    return .{
        .string_table_size = try reader.readIntLittle(u64),
        .string_data_size = try reader.readIntLittle(u64),
        .field_table_size = try reader.readIntLittle(u64),
        .field_data_size = try reader.readIntLittle(u64),
        .code_size = try reader.readIntLittle(u64),
        .entry_point = try reader.readIntLittle(u64),
    };
}

fn emitHeader(writer: anytype, header: Header) !void {
    try writer.writeAll("VeMd");
    try writer.writeIntLittle(u64, header.string_table_size);
    try writer.writeIntLittle(u64, header.string_data_size);
    try writer.writeIntLittle(u64, header.field_table_size);
    try writer.writeIntLittle(u64, header.field_data_size);
    try writer.writeIntLittle(u64, header.code_size);
    try writer.writeIntLittle(u64, header.entry_point);
}

fn loadTable(
    reader: anytype,
    table_size: u64,
    data_size: u64,
    allocator: Allocator,
) !Table {
    var data = try allocator.alloc(u8, data_size);
    errdefer allocator.free(data);
    try reader.readNoEof(data);

    var entries = try allocator.alloc([]const u8, table_size);
    errdefer allocator.free(entries);

    for (entries) |*entry| {
        const begin = try reader.readIntLittle(u64);
        const end = try reader.readIntLittle(u64);
        entry.* = data[begin..end];
    }

    return .{
        .data = data,
        .entries = entries,
    };
}

fn emitTable(
    writer: anytype,
    table: Table,
) !void {
    try writer.writeAll(table.data);

    for (table.entries) |entry| {
        const begin: u64 = @intFromPtr(entry.ptr) - @intFromPtr(table.data.ptr);
        const end: u64 = begin + entry.len;
        try writer.writeIntLittle(u64, begin);
        try writer.writeIntLittle(u64, end);
    }
}

fn loadInstruction(reader: anytype) !Instruction {
    const opcode = try meta.intToEnum(Opcode, try reader.readByte());

    const Operand = @TypeOf(@as(Instruction, undefined).operand);
    const operand: Operand = switch (opcode) {
        .pushf => std.debug.panic("Haven't figured out floats yet...", .{}),

        .pushs,
        .jmp,
        .jmpnz,
        .call,
        .stack_alloc,
        .list_load,
        .list_store,
        => .{ .location = try leb.readULEB128(u64, reader) },

        .struct_load,
        .struct_store,
        => .{ .field_id = try leb.readULEB128(u64, reader) },

        .push,
        .load,
        .store,
        .syscall,
        => .{ .int = try leb.readILEB128(i64, reader) },

        else => .{ .none = void{} },
    };

    return .{
        .op = opcode,
        .operand = operand,
    };
}

fn emitInstruction(writer: anytype, instruction: Instruction) !void {
    const opcode: u8 = @intFromEnum(instruction.op);
    try writer.writeByte(opcode);

    const operand = instruction.operand;

    switch (instruction.op) {
        .pushf => std.debug.panic("Haven't figured out floats yet...", .{}),

        .pushs,
        .jmp,
        .jmpnz,
        .call,
        .stack_alloc,
        .list_load,
        .list_store,
        => try leb.writeULEB128(writer, operand.location),

        .struct_load,
        .struct_store,
        => try leb.writeULEB128(writer, operand.field_id),

        .push,
        .load,
        .store,
        .syscall,
        => try leb.writeILEB128(writer, operand.int),

        else => {},
    }
}

test {
    const program = Program{
        .code = &.{},
        .entry = 0,
        .strings = &.{},
        .field_names = &.{},
        .deinit_data = .{
            .allocator = std.testing.allocator,
            .strings = &.{},
            .field_names = &.{},
        },
    };

    var output = ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    try emit(output.writer(), program);
}
