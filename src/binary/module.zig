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
    source_table_size: u64,
    source_data_size: u64,
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

    const source_table: ?Table = if (header.source_table_size > 0) try loadTable(
        reader,
        header.source_table_size,
        header.source_data_size,
        allocator,
    ) else null;

    const code = try allocator.alloc(Instruction, header.code_size);
    for (code) |*instruction| {
        instruction.* = try loadInstruction(reader);
    }

    return .{
        .code = code,
        .entry = header.entry_point,
        .strings = string_table.entries,
        .field_names = field_table.entries,
        .tokens = if (source_table) |tbl| tbl.entries else null,
        .deinit_data = .{
            .allocator = allocator,
            .strings = string_table.data,
            .field_names = field_table.data,
            .source = if (source_table) |tbl| tbl.data else null,
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
        .source_table_size = if (program.tokens) |toks| toks.len else 0,
        .source_data_size = if (deinit_data.source) |src| src.len else 0,
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

    if (program.tokens) |_| {
        const source_table = Table{
            .entries = program.tokens.?,
            .data = deinit_data.source.?,
        };
        try emitTable(writer, source_table);
    }

    for (program.code) |instruction| {
        try emitInstruction(writer, instruction);
    }
}

fn loadHeader(reader: anytype) !Header {
    if (!(try reader.isBytes("VeMd"))) return Error.InvalidFileID;
    return .{
        .string_table_size = try reader.readInt(u64, .little),
        .string_data_size = try reader.readInt(u64, .little),
        .field_table_size = try reader.readInt(u64, .little),
        .field_data_size = try reader.readInt(u64, .little),
        .source_table_size = try reader.readInt(u64, .little),
        .source_data_size = try reader.readInt(u64, .little),
        .code_size = try reader.readInt(u64, .little),
        .entry_point = try reader.readInt(u64, .little),
    };
}

fn emitHeader(writer: anytype, header: Header) !void {
    try writer.writeAll("VeMd");
    try writer.writeInt(u64, header.string_table_size, .little);
    try writer.writeInt(u64, header.string_data_size, .little);
    try writer.writeInt(u64, header.field_table_size, .little);
    try writer.writeInt(u64, header.field_data_size, .little);
    try writer.writeInt(u64, header.source_table_size, .little);
    try writer.writeInt(u64, header.source_data_size, .little);
    try writer.writeInt(u64, header.code_size, .little);
    try writer.writeInt(u64, header.entry_point, .little);
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

    const entries = try allocator.alloc([]const u8, table_size);
    errdefer allocator.free(entries);

    for (entries) |*entry| {
        const begin = try reader.readInt(u64, .little);
        const end = try reader.readInt(u64, .little);
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
        try writer.writeInt(u64, begin, .little);
        try writer.writeInt(u64, end, .little);
    }
}

fn loadInstruction(reader: anytype) !Instruction {
    const opcode = try meta.intToEnum(Opcode, try reader.readByte());

    const Operand = @TypeOf(@as(Instruction, undefined).operand);
    const operand: Operand = switch (opcode) {
        .pushf => .{ .float = try loadFloat(reader) },

        .pushs,
        .jmp,
        .jmpnz,
        .call,
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
        .stack_alloc,
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
        .pushf => try emitFloat(writer, operand.float),

        .pushs,
        .jmp,
        .jmpnz,
        .call,
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
        .stack_alloc,
        => try leb.writeILEB128(writer, operand.int),

        else => {},
    }
}

fn loadFloat(reader: anytype) !f64 {
    const int = try reader.readInt(u64, .little);
    return @bitCast(int);
}

fn emitFloat(writer: anytype, f: f64) !void {
    const int: u64 = @bitCast(f);
    try writer.writeInt(u64, int, .little);
}

test {
    const testing = std.testing;
    const fs = std.fs;
    const asm_ = @import("asm");
    const AsmError = asm_.Error;
    const Asm = asm_.Asm;
    const vm = @import("vm");
    const VMContext = vm.VMContext;
    const interpreter = vm.interpreter;

    const source =
        \\-string $hello "Hello"
        \\-string $good-bye "Good bye"
        \\
        \\-function $main
        \\-begin
        \\    pushs $hello
        \\    syscall %0
        \\    struct_alloc
        \\    dup
        \\    push %1
        \\    struct_store $x
        \\    dup
        \\    pushf @3.14
        \\    struct_store $y
        \\    syscall %0
        \\    pushs $good-bye
        \\    syscall %0
        \\    push %0
        \\    ret
        \\-end
    ;

    const expected_output =
        \\Hello
        \\{x: 1, y: 3.14}
        \\Good bye
        \\
    ;

    var errors = ArrayList(AsmError).init(testing.allocator);
    defer errors.deinit();

    var assembler = Asm.init(source, testing.allocator, &errors);
    defer assembler.deinit();

    try assembler.assemble();
    try testing.expectEqual(@as(usize, 0), errors.items.len);

    {
        var program = try assembler.getProgram(testing.allocator, .vemod);
        defer program.deinit();

        var output = try fs.cwd().createFile(".binary.test.vbf", .{});
        defer output.close();

        try emit(output.writer(), program);
    }

    var input = try fs.cwd().openFile(".binary.test.vbf", .{});
    defer {
        input.close();
        fs.cwd().deleteFile(".binary.test.vbf") catch unreachable;
    }

    var program = try load(input.reader(), testing.allocator);
    defer program.deinit();

    try testing.expectEqualSlices(u8, source, program.deinit_data.?.source.?);

    var output_buffer = ArrayList(u8).init(testing.allocator);
    defer output_buffer.deinit();

    const output_writer = output_buffer.writer();

    var context = VMContext.init(program, testing.allocator, &output_writer, false);
    defer context.deinit();

    try testing.expectEqual(@as(i64, 0), try interpreter.run(&context));

    try testing.expectEqualSlices(u8, expected_output, output_buffer.items);
}
