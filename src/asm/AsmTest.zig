const std = @import("std");
const Opcode = @import("arch").Opcode;
const Asm = @import("Asm.zig");
const Error = @import("Error.zig");

const Tag = @TypeOf(@as(Error, undefined).tag);

fn testCase(
    source: []const u8,
    expected_error_tag: Tag,
    expected_error_token: []const u8,
) !void {
    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(expected_error_tag, errors.items[0].tag);
    try std.testing.expectEqualStrings(expected_error_token, errors.items[0].where.?);
}

test "unexpected token" {
    const source =
        \\-function $main
        \\-begin
        \\push .label
        \\-end
    ;

    try testCase(source, .@"Unexpected token", "label");
}

test "duplicate label" {
    const source =
        \\-function $main
        \\-begin
        \\.label
        \\.label
        \\-end
    ;

    try testCase(source, .@"Duplicate label or function", "label");
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

    try testCase(source, .@"Duplicate label or function", "main");
}

test "unresolved label" {
    const source =
        \\-function $main
        \\-begin
        \\jmp .label
        \\-end
    ;

    try testCase(source, .@"Unresolved label or function", "label");
}

test "unresolved function" {
    const source =
        \\-function $main
        \\-begin
        \\call $func
        \\-end
    ;

    try testCase(source, .@"Unresolved label or function", "func");
}

test "success" {
    const source =
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
        \\add
        \\jmp .label
        \\stack_alloc %1000000
        \\.label
        \\ret
        \\-end
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();

    try std.testing.expectEqual(@as(usize, 0), errors.items.len);
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

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();
    const code = asm_.code.items;

    try std.testing.expectEqual(@as(usize, 0), errors.items.len);
    try std.testing.expectEqual(@as(usize, 6), code.len);
    try std.testing.expectEqual(Opcode.call, code[0].op);
    try std.testing.expectEqual(@as(usize, 5), code[0].operand.location);
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

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();
    const code = asm_.code.items;

    try std.testing.expectEqual(@as(usize, 0), errors.items.len);
    try std.testing.expectEqual(@as(usize, 4), code.len);
    try std.testing.expectEqual(Opcode.jmp, code[0].op);
    try std.testing.expectEqual(@as(usize, 3), code[0].operand.location);
}

test "no main" {
    const source =
        \\-function $not_main
        \\-begin
        \\-end
    ;

    var errors = std.ArrayList(Error).init(std.testing.allocator);
    defer errors.deinit();

    var asm_ = Asm.init(source, std.testing.allocator, &errors);
    defer asm_.deinit();

    try asm_.assemble();
    try std.testing.expectEqual(@as(usize, 1), errors.items.len);
    try std.testing.expectEqual(Tag.@"No main function", errors.items[0].tag);
}
