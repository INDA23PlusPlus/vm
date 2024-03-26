//!
//! Generic error type that can be shared between assembler and compiler
//!
const Self = @This();
const SourceRef = @import("SourceRef.zig");

/// The kind of error
tag: enum {
    /// Invalid character in input stream
    invalid_character,
    /// (Assembler) Word following keyword prefix is not a valid keyword
    invalid_keyword,
    /// (Assembler) Word is not a valid instruction
    invalid_instruction,
    /// (Assembler) Word following literal prefix is not a valid literal
    invalid_literal,
    /// (Assembler) String literal has no closing double quote
    unterminated_string,
    /// (Assembler) Operand is missing from multibyte instruction
    missing_operand,
    /// (Assembler) Operand is supplied for instruction that does not take operands
    redundant_operand,
    /// (Assembler) Referenced label or function is not declared in this scope
    unresolved_label_or_function,
    /// (Assembler) Duplicate label or function
    duplicate_label_or_function,
    /// No main function
    no_main,
    /// Unexpected token in input stream
    unexpected_token,
    /// Unexpected end of input stream
    unexpected_eof,
},
/// Location in source
where: ?[]const u8 = null,
/// Optional error info
extra: ?[]const u8 = null,

/// Prints error with source location
pub fn print(self: Self, source: []const u8, writer: anytype) !void {
    var ref: SourceRef = undefined;
    if (self.where) |where| {
        ref = try SourceRef.init(source, where);
        try writer.print("Error on line {d}: {s}", .{ ref.line_num, @tagName(self.tag) });
    } else {
        try writer.print("Error: {s}", .{@tagName(self.tag)});
    }

    if (self.extra) |extra| {
        try writer.print(": {s}", .{extra});
    }
    try writer.print(".\n", .{});
    if (self.where) |_| {
        try ref.print(writer);
    }
}
