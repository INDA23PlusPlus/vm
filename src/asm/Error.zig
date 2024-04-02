//!
//! Generic error type that can be shared between assembler and compiler
//!
const Self = @This();
const SourceRef = @import("SourceRef.zig");

/// The kind of error
tag: enum {
    /// Invalid character in input stream
    @"Invalid character",
    /// (Assembler) Word following keyword prefix is not a valid keyword
    @"Invalid keyword",
    /// (Assembler) Word is not a valid instruction
    @"Invalid instruction",
    /// (Assembler) Word following literal prefix is not a valid literal
    @"Invalid literal",
    /// (Assembler) String literal has no closing double quote
    @"Unterminated string",
    /// (Assembler) Operand is missing from multibyte instruction
    @"Missing operand",
    /// (Assembler) Operand is supplied for instruction that does not take operands
    @"Redundant operand",
    /// (Assembler) Referenced label or function is not declared in this scope
    @"Unresolved label or function",
    /// (Assembler) Duplicate label or function
    @"Duplicate label or function",
    /// No main function
    @"No main function",
    /// Unexpected token in input stream
    @"Unexpected token",
    /// Unexpected end of input stream
    @"Unexpected end of input",
},
/// Location in source
where: ?[]const u8 = null,
/// Optional error info
extra: ?[]const u8 = null,
/// Related location
related: ?[]const u8 = null,
/// Related location message
related_msg: ?[]const u8 = null,

/// Prints error with source location
pub fn print(self: Self, source: []const u8, writer: anytype) !void {
    // TODO: print related information
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
