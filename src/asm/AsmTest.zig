const std = @import("std");
const Opcode = @import("arch").Opcode;
const Asm = @import("Asm.zig");
const DiagnosticList = @import("diagnostic").DiagnosticList;

fn testCase(
    source: []const u8,
    expected_error_token: []const u8,
) !void {
    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();
    try std.testing.expectEqual(@as(usize, 1), diagnostics.list.items.len);
    try std.testing.expectEqualStrings(expected_error_token, diagnostics.list.items[0].location.?);
}

test "unexpected token" {
    const source =
        \\-function $main
        \\-begin
        \\push .label
        \\-end
    ;

    try testCase(source, "label");
}

test "duplicate label" {
    const source =
        \\-function $main
        \\-begin
        \\.label
        \\.label
        \\-end
    ;

    try testCase(source, "label");
}

test "duplicate function" {
    const source =
        \\-function $main
        \\-begin
        \\-end
        \\-function $main
        \\-begin
        \\-end
    ;

    try testCase(source, "main");
}

test "duplicate string" {
    const source =
        \\-string $string "hej"
        \\-string $string "nej"
        \\-function $main
        \\-begin
        \\-end
    ;

    try testCase(source, "string");
}

test "unresolved label" {
    const source =
        \\-function $main
        \\-begin
        \\jmp .label
        \\-end
    ;

    try testCase(source, "label");
}

test "unresolved function" {
    const source =
        \\-function $main
        \\-begin
        \\call $func
        \\-end
    ;

    try testCase(source, "func");
}

test "unresolved string" {
    const source =
        \\-function $main
        \\-begin
        \\pushs $string
        \\-end
    ;

    try testCase(source, "string");
}

test "invalid escape character" {
    const source =
        \\-string $message "Hello \m there!"
        \\-function $main
        \\-begin
        \\-end
    ;

    try testCase(source, "m");
}

test "success" {
    const source =
        \\-string $message "My name is:\n" "\"Ludvig\""
        \\-function $main
        \\-begin
        \\call $other
        \\-end
        \\
        \\-function $other
        \\-begin
        \\push %0
        \\pushf @3.1415
        \\load %0
        \\pushs $message
        \\struct_load $hello
        \\struct_store $goodbye
        \\add
        \\jmp .label
        \\stack_alloc %1000000
        \\.label
        \\ret
        \\-end
    ;

    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();

    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
    try std.testing.expectEqual(@as(usize, 0), asm_.entry.?);
}

test "patching calls" {
    const source =
        \\-function $main
        \\-begin
        \\call $other  #0
        \\push %0      #1 (doing some other stuff to make it interesting)
        \\pop          #2
        \\load %0      #3
        \\store %0     #4
        \\-end
        \\
        \\-function $other
        \\-begin
        \\push %0      #5
        \\-end
    ;

    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();
    const code = asm_.code.items;

    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
    try std.testing.expectEqual(@as(usize, 10), code.len);
    try std.testing.expectEqual(Opcode.call, code[0].op);
    try std.testing.expectEqual(@as(usize, 7), code[0].operand.location);
}

test "patching labels" {
    const source =
        \\-function $main
        \\-begin
        \\jmp .label   #0
        \\push %0      #1
        \\pop          #2
        \\.label
        \\load %0      #3
        \\-end
    ;

    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();
    const code = asm_.code.items;

    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
    try std.testing.expectEqual(@as(usize, 6), code.len);
    try std.testing.expectEqual(Opcode.jmp, code[0].op);
    try std.testing.expectEqual(@as(usize, 3), code[0].operand.location);
}

test "no main" {
    const source =
        \\-function $not_main
        \\-begin
        \\-end
    ;

    var diagnostics = DiagnosticList.init(std.testing.allocator, source);
    defer diagnostics.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &diagnostics);
    defer asm_.deinit();

    try asm_.assemble();
    try std.testing.expectEqual(@as(usize, 1), diagnostics.list.items.len);
}
