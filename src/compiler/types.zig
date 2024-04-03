const std = @import("std");
const ArrayList = std.ArrayList;

/// A possible Symbol for either a node or a token
pub const Node_Symbol = enum {
    STATEMENTS,
    END_OF_STATEMENTS,
    STATEMENT,

    VARIABLE_DECLARATION,
    VARIABLE_MUTATION,
    FUNCTION_DECLARATION,
    LOOP,
    IF_STATEMENT,
    ELIF_STATEMENT,
    ELSE_STATEMENT,
    CHAIN_STATEMENT,
    FUNCTION_CALL,
    RET_STATEMENT,
    CHAIN_CASE,

    EXPRESSION,
    FUNCTION_HEADER,
    SCOPE,
    WHILE_LOOP,
    FOR_LOOP,
    FUNCTION_ARGUMENTS,

    MUTATION_OPERATOR,
    OPERATOR,
    LITERAL,
    STRUCT_ACCESS,
    LIST_ACCESS,
    FUNCTION_PARAMETERS,
    FOR_HEADER,

    STRUCT_LITERAL,
    LIST_LITERAL,

    STRUCT_FIELDS,
    LIST_ELEMENTS,

    STRUCT_FIELD,

    IDENTIFIER,
    FLOAT,
    INT,
    STRING,
    DEF,
    RET,
    IF,
    ELSE,
    WHILE,
    FOR,
    CHAIN,
    BREAK,

    COLON_EQUALS,
    COLON,
    SEMICOLON,
    COMMA,
    DOT,
    OPEN_CURLY,
    CLOSED_CURLY,
    OPEN_PARENTHESIS,
    CLOSED_PARENTHESIS,
    OPEN_SQUARE,
    CLOSED_SQUARE,
    PLUS,
    MINUS,
    TIMES,
    DIVIDE,
    REM,
    MOD,
    AND,
    OR,
    NOT,
    EQUALS,
    NOT_EQUALS,
    LESS_THAN,
    GREATER_THAN,
    LESS_THAN_EQUALS,
    GREATER_THAN_EQUALS,
    ASSIGN,
    PLUS_ASSIGN,
    MINUS_ASSIGN,
    TIMES_ASSIGN,
    DIVIDE_ASSIGN,
    END_OF_FILE,
};

/// Token that the lexer generates
pub const Token = struct {
    kind: Node_Symbol, //
    content: []const u8,
    cl_start: u32,
    cl_end: u32,
    ln_start: u32,
    ln_end: u32,
};

/// Node that the parser generates
pub const Node = struct {
    symbol: Node_Symbol,
    content: []const u8,
};
