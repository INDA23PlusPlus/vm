const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const Lexer = @import("Lexer.zig");

const Node_Symbol = types.Node_Symbol;
const Token = types.Token;
const Node = types.Node;

const Parse_Tree = struct { node: Node, branches: std.ArrayList(Parse_Tree) };

const Token_Reader = struct { tokens: std.ArrayList(Token), token_index: u32 };

// returns true if a sequence of tokens (e.g { IDENTIFIER, COLON_EQUALS }) can be found at the current token_index
pub fn peek(tokens: anytype, token_reader: *Token_Reader) bool {
    const token_count = @typeInfo(@TypeOf(tokens)).Array.len;
    const start_index: u32 = token_reader.*.token_index;

    for (0..token_count) |i| {
        const token_index = start_index + i;

        if (token_index >= token_reader.*.tokens.items.len) {
            return false;
        }

        if (tokens[i] != token_reader.tokens.items[token_index].kind) {
            return false;
        }
    }

    return true;
}

pub fn get_token(token_reader: *Token_Reader) Token {
    const token = token_reader.*.tokens.items[token_reader.*.token_index];

    token_reader.*.token_index += 1;

    return token;
}

pub fn parse_statements(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (token_reader.*.token_index >= token_reader.*.tokens.items.len) {
        return parse_symbols([_]Node_Symbol{.END_OF_STATEMENTS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CLOSED_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_STATEMENTS}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .STATEMENT, .STATEMENTS }, node_branch, token_reader);
}

pub fn parse_statement(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{ .IDENTIFIER, .COLON_EQUALS }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_DECLARATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .ASSIGN }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .PLUS_ASSIGN }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .MINUS_ASSIGN }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .TIMES_ASSIGN }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .DIVIDE_ASSIGN }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .DOT }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .OPEN_SQUARE }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.VARIABLE_MUTATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .DEF, .IDENTIFIER }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.FUNCTION_DECLARATION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.WHILE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.WHILE_LOOP}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.FOR}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.FOR_LOOP}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.IF}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.IF_STATEMENT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .ELSE, .IF }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.ELIF_STATEMENT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.ELSE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.ELSE_STATEMENT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CHAIN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.CHAIN_STATEMENT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.OPEN_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.SCOPE}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .OPEN_PARENTHESIS }, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .FUNCTION_CALL, .SEMICOLON }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.RET}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.RET_STATEMENT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.BREAK}, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .BREAK, .SEMICOLON }, node_branch, token_reader);
    }

    return false;
}

pub fn parse_variable_declaration(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .COLON_EQUALS, .EXPRESSION, .SEMICOLON }, node_branch, token_reader);
}

pub fn parse_variable_mutation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{ .IDENTIFIER, .OPEN_SQUARE }, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .LIST_ACCESS, .MUTATION_OPERATOR, .EXPRESSION, .SEMICOLON }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .DOT }, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .STRUCT_ACCESS, .MUTATION_OPERATOR, .EXPRESSION, .SEMICOLON }, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .MUTATION_OPERATOR, .EXPRESSION, .SEMICOLON }, node_branch, token_reader);
}

pub fn parse_function_declaration(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .DEF, .IDENTIFIER, .OPEN_PARENTHESIS, .FUNCTION_PARAMETERS, .CLOSED_PARENTHESIS, .SCOPE }, node_branch, token_reader);
}

pub fn parse_while_loop(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .WHILE, .OPEN_PARENTHESIS, .EXPRESSION, .CLOSED_PARENTHESIS, .SCOPE }, node_branch, token_reader);
}

pub fn parse_for_loop(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .FOR, .FOR_HEADER, .SCOPE }, node_branch, token_reader);
}

pub fn parse_if_statement(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IF, .OPEN_PARENTHESIS, .EXPRESSION, .CLOSED_PARENTHESIS, .SCOPE }, node_branch, token_reader);
}

pub fn parse_elif_statement(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .ELSE, .IF, .OPEN_PARENTHESIS, .EXPRESSION, .CLOSED_PARENTHESIS, .SCOPE }, node_branch, token_reader);
}

pub fn parse_else_statement(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .ELSE, .SCOPE }, node_branch, token_reader);
}

pub fn parse_scope(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .OPEN_CURLY, .STATEMENTS, .CLOSED_CURLY }, node_branch, token_reader);
}

pub fn parse_function_call(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .OPEN_PARENTHESIS, .FUNCTION_ARGUMENTS, .CLOSED_PARENTHESIS }, node_branch, token_reader);
}

pub fn parse_return(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{ .RET, .SEMICOLON }, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .RET, .SEMICOLON }, node_branch, token_reader);
    } else {
        return parse_symbols([_]Node_Symbol{ .RET, .EXPRESSION, .SEMICOLON }, node_branch, token_reader);
    }
}

pub fn parse_expression(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .TERM, .EXPRESSION_CONTINUATION }, node_branch, token_reader);
}

pub fn parse_function_parameters(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{ .IDENTIFIER, .COMMA }, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .COMMA, .FUNCTION_PARAMETERS }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .CLOSED_PARENTHESIS }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.IDENTIFIER}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CLOSED_PARENTHESIS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NO_PARAMETERS}, node_branch, token_reader);
    }

    return false;
}

pub fn parse_for_header(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .OPEN_PARENTHESIS, .IDENTIFIER, .COLON_EQUALS, .EXPRESSION, .SEMICOLON, .EXPRESSION, .SEMICOLON, .IDENTIFIER, .MUTATION_OPERATOR, .EXPRESSION, .CLOSED_PARENTHESIS }, node_branch, token_reader);
}

pub fn parse_function_arguments(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.CLOSED_PARENTHESIS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NO_ARGUMENTS}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .EXPRESSION, .CALL_CONTINUATION }, node_branch, token_reader);
}

pub fn parse_call_continuation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.COMMA}, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .COMMA, .FUNCTION_ARGUMENTS }, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{.NO_ARGUMENTS}, node_branch, token_reader);
}

pub fn parse_term(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.OPEN_PARENTHESIS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .OPEN_PARENTHESIS, .EXPRESSION, .CLOSED_PARENTHESIS }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.MINUS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .MINUS, .EXPRESSION }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.NOT}, token_reader)) {
        return parse_symbols([_]Node_Symbol{ .NOT, .EXPRESSION }, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.FLOAT}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.FLOAT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.INT}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.INT}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.STRING}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.STRING}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .OPEN_CURLY, .IDENTIFIER, .COLON }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.STRUCT_LITERAL}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.OPEN_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.LIST_LITERAL}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.OPEN_SQUARE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.LIST_LITERAL}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .OPEN_PARENTHESIS }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.FUNCTION_CALL}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .DOT }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.STRUCT_ACCESS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{ .IDENTIFIER, .OPEN_SQUARE }, token_reader)) {
        return parse_symbols([_]Node_Symbol{.LIST_ACCESS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.IDENTIFIER}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.IDENTIFIER}, node_branch, token_reader);
    }

    return false;
}

pub fn parse_expression_continuation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.SEMICOLON}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_EXPRESSION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.COMMA}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_EXPRESSION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CLOSED_PARENTHESIS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_EXPRESSION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CLOSED_SQUARE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_EXPRESSION}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.CLOSED_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.END_OF_EXPRESSION}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .OPERATOR, .EXPRESSION }, node_branch, token_reader);
}

pub fn parse_mutation_operator(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.ASSIGN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.ASSIGN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.PLUS_ASSIGN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.PLUS_ASSIGN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.MINUS_ASSIGN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.MINUS_ASSIGN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.TIMES_ASSIGN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.TIMES_ASSIGN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.DIVIDE_ASSIGN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.DIVIDE_ASSIGN}, node_branch, token_reader);
    }

    return false;
}

pub fn parse_operator(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.PLUS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.PLUS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.MINUS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.MINUS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.TIMES}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.TIMES}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.DIVIDE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.DIVIDE}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.REM}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.REM}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.MOD}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.MOD}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.EQUALS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.EQUALS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.NOT_EQUALS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NOT_EQUALS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.AND}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.AND}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.OR}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.OR}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.GREATER_THAN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.GREATER_THAN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.LESS_THAN}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.LESS_THAN}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.GREATER_THAN_EQUALS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.GREATER_THAN_EQUALS}, node_branch, token_reader);
    }
    if (peek([_]Node_Symbol{.LESS_THAN_EQUALS}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.LESS_THAN_EQUALS}, node_branch, token_reader);
    }

    return false;
}

pub fn parse_struct_access(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .DOT, .IDENTIFIER }, node_branch, token_reader);
}

pub fn parse_list_access(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .OPEN_SQUARE, .EXPRESSION, .CLOSED_SQUARE }, node_branch, token_reader);
}

pub fn parse_struct_literal(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .OPEN_CURLY, .STRUCT_FIELDS, .CLOSED_CURLY }, node_branch, token_reader);
}

pub fn parse_list_literal(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .OPEN_CURLY, .LIST_ELEMENTS, .CLOSED_CURLY }, node_branch, token_reader);
}

pub fn parse_struct_fields(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    return parse_symbols([_]Node_Symbol{ .IDENTIFIER, .COLON, .EXPRESSION, .FIELD_CONTINUATION }, node_branch, token_reader);
}

pub fn parse_field_continuation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.CLOSED_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NO_FIELDS}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .COMMA, .STRUCT_FIELDS }, node_branch, token_reader);
}

pub fn parse_list_elements(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.CLOSED_CURLY}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NO_ELEMENTS}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .EXPRESSION, .LIST_CONTINUATION }, node_branch, token_reader);
}

pub fn parse_list_continuation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    if (peek([_]Node_Symbol{.CLOSED_SQUARE}, token_reader)) {
        return parse_symbols([_]Node_Symbol{.NO_ELEMENTS}, node_branch, token_reader);
    }

    return parse_symbols([_]Node_Symbol{ .COMMA, .LIST_ELEMENTS }, node_branch, token_reader);
}

pub fn parse_symbol(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    const symbol = node_branch.*.node.symbol;
    const symbols = [_]Node_Symbol{symbol};

    switch (symbol) {
        .STATEMENTS => {
            return parse_statements(node_branch, token_reader);
        },
        .STATEMENT => {
            return parse_statement(node_branch, token_reader);
        },
        .END_OF_STATEMENTS => {
            return true;
        },
        .VARIABLE_DECLARATION => {
            return parse_variable_declaration(node_branch, token_reader);
        },
        .VARIABLE_MUTATION => {
            return parse_variable_mutation(node_branch, token_reader);
        },
        .FUNCTION_DECLARATION => {
            return parse_function_declaration(node_branch, token_reader);
        },
        .NO_PARAMETERS => {
            return true;
        },
        .WHILE_LOOP => {
            return parse_while_loop(node_branch, token_reader);
        },
        .FOR_LOOP => {
            return parse_for_loop(node_branch, token_reader);
        },
        .IF_STATEMENT => {
            return parse_if_statement(node_branch, token_reader);
        },
        .ELIF_STATEMENT => {
            return parse_elif_statement(node_branch, token_reader);
        },
        .ELSE_STATEMENT => {
            return parse_else_statement(node_branch, token_reader);
        },
        .SCOPE => {
            return parse_scope(node_branch, token_reader);
        },
        .FUNCTION_CALL => {
            return parse_function_call(node_branch, token_reader);
        },
        .RET_STATEMENT => {
            return parse_return(node_branch, token_reader);
        },
        .EXPRESSION => {
            return parse_expression(node_branch, token_reader);
        },
        .FUNCTION_PARAMETERS => {
            return parse_function_parameters(node_branch, token_reader);
        },
        .FOR_HEADER => {
            return parse_for_header(node_branch, token_reader);
        },
        .FUNCTION_ARGUMENTS => {
            return parse_function_arguments(node_branch, token_reader);
        },
        .CALL_CONTINUATION => {
            return parse_call_continuation(node_branch, token_reader);
        },
        .NO_ARGUMENTS => {
            return true;
        },
        .TERM => {
            return parse_term(node_branch, token_reader);
        },
        .EXPRESSION_CONTINUATION => {
            return parse_expression_continuation(node_branch, token_reader);
        },
        .END_OF_EXPRESSION => {
            return true;
        },
        .MUTATION_OPERATOR => {
            return parse_mutation_operator(node_branch, token_reader);
        },
        .OPERATOR => {
            return parse_operator(node_branch, token_reader);
        },
        .STRUCT_ACCESS => {
            return parse_struct_access(node_branch, token_reader);
        },
        .LIST_ACCESS => {
            return parse_list_access(node_branch, token_reader);
        },
        .STRUCT_LITERAL => {
            return parse_struct_literal(node_branch, token_reader);
        },
        .LIST_LITERAL => {
            return parse_list_literal(node_branch, token_reader);
        },
        .STRUCT_FIELDS => {
            return parse_struct_fields(node_branch, token_reader);
        },
        .FIELD_CONTINUATION => {
            return parse_field_continuation(node_branch, token_reader);
        },
        .NO_FIELDS => {
            return true;
        },
        .LIST_ELEMENTS => {
            return parse_list_elements(node_branch, token_reader);
        },
        .LIST_CONTINUATION => {
            return parse_list_continuation(node_branch, token_reader);
        },
        .NO_ELEMENTS => {
            return true;
        },
        else => { // tokens
            if (peek(symbols, token_reader)) {
                const token = get_token(token_reader);
                node_branch.*.node.symbol = token.kind;
                node_branch.*.node.content = token.content;
                return true;
            }
        },
    }

    return false;
}

// parses a list of symbols (e.g { IDENTIFIER, ASSIGN, EXPRESSION, SEMICOLON })
pub fn parse_symbols(symbols: anytype, node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var branches = std.ArrayList(Parse_Tree).init(allocator);

    const symbol_count = @typeInfo(@TypeOf(symbols)).Array.len;

    for (0..symbol_count) |i| {
        const symbol = symbols[i];
        var branch = Parse_Tree{ .node = Node{ .symbol = symbol, .content = "" }, .branches = std.ArrayList(Parse_Tree).init(allocator) };

        if (parse_symbol(&branch, token_reader)) {
            branches.append(branch) catch {};
        } else {
            std.debug.print("Failed to parse {s}\n", .{@tagName(symbol)});

            return false;
        }
    }

    node_branch.branches = branches;

    return true;
}

pub fn print_indentation(indentation: u32) void {
    for (0..indentation) |_| {
        std.debug.print("  ", .{});
    }
}

// prints the parse tree in a nice format so that we can more easily check that it's correct
pub fn print_parse_tree(parse_tree: *Parse_Tree, recursion_depth: u32) void {
    const node = parse_tree.*.node;
    const symbol = node.symbol;
    const content = node.content;

    print_indentation(recursion_depth);
    std.debug.print("symbol: {s}\n", .{@tagName(symbol)});

    switch (symbol) {
        .IDENTIFIER, .FLOAT, .INT, .STRING => {
            print_indentation(recursion_depth);
            std.debug.print("content: \"{s}\"\n", .{content});
        },
        else => {},
    }

    const branches = parse_tree.*.branches;

    for (0..branches.items.len) |i| {
        print_indentation(recursion_depth);
        std.debug.print("{{\n", .{});

        print_parse_tree(&(branches.items[i]), recursion_depth + 1);

        print_indentation(recursion_depth);
        std.debug.print("}}\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();

    var file = try cwd.openFile("docs/example.vmlang", .{ .mode = .read_only });
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, comptime std.math.maxInt(usize));

    var lexer = Lexer.init(allocator);
    defer lexer.deinit();

    try lexer.tokenize(file_content);

    var token_reader = Token_Reader{ .tokens = lexer.tokens, .token_index = 0 };

    var parse_tree = Parse_Tree{ .node = Node{ .symbol = .STATEMENTS, .content = "" }, .branches = std.ArrayList(Parse_Tree).init(allocator) };

    if (parse_symbol(&parse_tree, &token_reader)) {
        std.debug.print("The parser finished sucessfully.\n\n", .{});

        print_parse_tree(&parse_tree, 0);
    }
}
