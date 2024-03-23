const std = @import("std");
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
        \\-function "main"
        \\-begin
        \\push .label
        \\-end
    ;

    try testCase(source, .unexpected_token, "label");
}

test "duplicate label" {
    const source =
        \\-function "main"
        \\-begin
        \\.label
        \\.label
        \\-end
    ;

    try testCase(source, .duplicate_label_or_function, "label");
}

test "duplicate function" {
    const source =
        \\-function "main"
        \\-begin
        \\-end
        \\-function "main"
        \\-begin
        \\-end
    ;

    try testCase(source, .duplicate_label_or_function, "main");
}

test "unresolved label" {
    const source =
        \\-function "main"
        \\-begin
        \\jmp .label
        \\-end
    ;

    try testCase(source, .unresolved_label_or_function, "label");
}

test "unresolved function" {
    const source =
        \\-function "main"
        \\-begin
        \\call "func"
        \\-end
    ;

    try testCase(source, .unresolved_label_or_function, "func");
}

test "success" {
    const source =
        \\-function "main"
        \\-begin
        \\call "other"
        \\-end
        \\
        \\-function "other"
        \\-begin
        \\push %0
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
}
