const std = @import("std");
const types = @import("types.zig");

const Node_Symbol = types.Node_Symbol;
const Node = types.Node;

const Parse_Tree = struct { node: Node, branches: std.ArrayList(Parse_Tree) };

const Token_Reader = struct { tokens: std.ArrayList(Node), token_index: u32 };

// returns true if a sequence of tokens (e.g { IDENTIFIER, COLON_EQUALS }) can be found at the current token_index
pub fn peak(tokens: []Node_Symbol, token_reader: *Token_Reader) bool {
    const  start_index: u32 = token_reader.*.token_index;
    var i: u32 = 0;

    while (i < tokens.len) : (i += 1) {
        const token_index = start_index + i;

        if (token_index >= token_reader.*.tokens.items.len) {
            return false;
        }

        if (tokens[i] != token_reader.tokens.items[token_index].symbol) {
            return false;
        }
    }

    return true;
}

pub fn get_token(token_reader: *Token_Reader) Node {
    const  token = token_reader.*.tokens.items[token_reader.*.token_index];

    token_reader.*.token_index += 1;

    return token;
}

pub fn parse_statements(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    {
        var peak_symbols = [_]Node_Symbol{Node_Symbol.END_OF_FILE}; // if we encounter an END_OF_FILE token then we are at the end of the statements
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.END_OF_STATEMENTS};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{Node_Symbol.CLOSED_CURLY}; // if we encounter a CLOSED_CURLY token then we are at the end of the statements
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.END_OF_STATEMENTS};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var symbols = [_]Node_Symbol{ Node_Symbol.STATEMENT, Node_Symbol.STATEMENTS };
        return parse_symbols(&symbols, node_branch, token_reader);
    }
}

// not all types of statements have been included here yet
pub fn parse_statement(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    {
        var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.COLON_EQUALS };
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.VARIABLE_DECLARATION};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.ASSIGN };
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.VARIABLE_MUTATION};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{ Node_Symbol.DEF, Node_Symbol.IDENTIFIER };
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.FUNCTION_DECLARATION};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }

    return false;
}

pub fn parse_variable_declaration(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.COLON_EQUALS, Node_Symbol.EXPRESSION, Node_Symbol.SEMICOLON };
    return parse_symbols(&peak_symbols, node_branch, token_reader);
}

pub fn parse_variable_mutation(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.MUTATION_OPERATOR, Node_Symbol.EXPRESSION, Node_Symbol.SEMICOLON };
    return parse_symbols(&peak_symbols, node_branch, token_reader);
}

pub fn parse_function_declaration(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var peak_symbols = [_]Node_Symbol{ Node_Symbol.DEF, Node_Symbol.FUNCTION_HEADER, Node_Symbol.SCOPE };
    return parse_symbols(&peak_symbols, node_branch, token_reader);
}

pub fn parse_function_header(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.OPEN_PARENTHESIS, Node_Symbol.FUNCTION_PARAMETERS, Node_Symbol.CLOSED_PARENTHESIS };
    return parse_symbols(&peak_symbols, node_branch, token_reader);
}

pub fn parse_scope(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var peak_symbols = [_]Node_Symbol{ Node_Symbol.OPEN_CURLY, Node_Symbol.STATEMENTS, Node_Symbol.CLOSED_CURLY };
    return parse_symbols(&peak_symbols, node_branch, token_reader);
}

pub fn parse_function_parameters(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    {
        var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.COMMA };
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.COMMA, Node_Symbol.FUNCTION_PARAMETERS };
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{ Node_Symbol.IDENTIFIER, Node_Symbol.CLOSED_PARENTHESIS };
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.IDENTIFIER};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }

    return false;
}

// this function is not finished at all, only handles identifiers and some literals atm.
pub fn parse_expression(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    {
        var peak_symbols = [_]Node_Symbol{Node_Symbol.IDENTIFIER};
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.IDENTIFIER};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{Node_Symbol.CONSTANT};
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.CONSTANT};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }
    {
        var peak_symbols = [_]Node_Symbol{Node_Symbol.STRING};
        if (peak(&peak_symbols, token_reader)) {
            var symbols = [_]Node_Symbol{Node_Symbol.STRING};
            return parse_symbols(&symbols, node_branch, token_reader);
        }
    }

    return false;
}

pub fn parse_symbol(node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    const symbol = node_branch.*.node.symbol;
    var symbols = [_]Node_Symbol{symbol};

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
        .FUNCTION_HEADER => {
            return parse_function_header(node_branch, token_reader);
        },
        .SCOPE => {
            return parse_scope(node_branch, token_reader);
        },
        .FUNCTION_PARAMETERS => {
            return parse_function_parameters(node_branch, token_reader);
        },
        .EXPRESSION => {
            return parse_expression(node_branch, token_reader);
        },
        .IDENTIFIER, .CONSTANT, .STRING, .DEF, .IF, .WHILE, .FOR, .CHAIN, .BREAK, .COLON_EQUALS, .COLON, .SEMICOLON, .COMMA, .ASSIGN, .OPEN_CURLY, .CLOSED_CURLY, .OPEN_PARENTHESIS, .CLOSED_PARENTHESIS => {
            if (peak(&symbols, token_reader)) {
                node_branch.*.node = get_token(token_reader);
                return true;
            }
        },
        else => {
            return false;
        },
    }

    return false;
}

// parses a list of symbols (e.g { IDENTIFIER, ASSIGN, EXPRESSION, SEMICOLON })
pub fn parse_symbols(symbols: []Node_Symbol, node_branch: *Parse_Tree, token_reader: *Token_Reader) bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var branches = std.ArrayList(Parse_Tree).init(allocator);

    var i: u32 = 0;

    while (i < symbols.len) : (i += 1) {
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
    var i: u32 = 0;
    while (i < indentation) : (i += 1) {
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
        .IDENTIFIER, .CONSTANT, .STRING => {
            print_indentation(recursion_depth);
            std.debug.print("content: \"{s}\"\n", .{content});
        },
        else => {},
    }

    var branches = parse_tree.*.branches;

    var i: u32 = 0;
    while (i < branches.items.len) : (i += 1) {
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

    var tokens = std.ArrayList(Node).init(allocator);

    //  manually inputing

    //  def function(a, b) {
    //      x := 10;
    //  }

    // as a test case

    try tokens.append(Node{ .symbol = Node_Symbol.DEF, .content = "def" });
    try tokens.append(Node{ .symbol = Node_Symbol.IDENTIFIER, .content = "function" });
    try tokens.append(Node{ .symbol = Node_Symbol.OPEN_PARENTHESIS, .content = "(" });
    try tokens.append(Node{ .symbol = Node_Symbol.IDENTIFIER, .content = "a" });
    try tokens.append(Node{ .symbol = Node_Symbol.COMMA, .content = "," });
    try tokens.append(Node{ .symbol = Node_Symbol.IDENTIFIER, .content = "b" });
    try tokens.append(Node{ .symbol = Node_Symbol.CLOSED_PARENTHESIS, .content = ")" });
    try tokens.append(Node{ .symbol = Node_Symbol.OPEN_CURLY, .content = "{" });
    try tokens.append(Node{ .symbol = Node_Symbol.IDENTIFIER, .content = "x" });
    try tokens.append(Node{ .symbol = Node_Symbol.COLON_EQUALS, .content = ":=" });
    try tokens.append(Node{ .symbol = Node_Symbol.CONSTANT, .content = "10" });
    try tokens.append(Node{ .symbol = Node_Symbol.SEMICOLON, .content = ";" });
    try tokens.append(Node{ .symbol = Node_Symbol.CLOSED_CURLY, .content = "}" });
    try tokens.append(Node{ .symbol = Node_Symbol.END_OF_FILE, .content = "" });

    var token_reader = Token_Reader{ .tokens = tokens, .token_index = 0 };

    var parse_tree = Parse_Tree{ .node = Node{ .symbol = Node_Symbol.STATEMENTS, .content = "" }, .branches = std.ArrayList(Parse_Tree).init(allocator) };

    if (parse_symbol(&parse_tree, &token_reader)) {
        std.debug.print("The parser finished sucessfully.\n\n", .{});

        print_parse_tree(&parse_tree, 0);
    }
}
