//!
//! Completion support for VeMod assembly
//!

const std = @import("std");
const lsp = @import("lsp.zig");
const asm_ = @import("asm");
const arch = @import("arch");

pub fn computeCompletions(
    position: lsp.Position,
    text: []const u8,
    list: *std.ArrayList(lsp.CompletionItem),
) !void {

    // Turn position in to an offset
    var line: i32 = 0;
    var column: i32 = 0;
    var offset: i32 = undefined;

    for (0.., text) |i, c| {
        if (line == position.line and column == position.character) {
            offset = @intCast(i);
            break;
        }
        if (c == '\n') {
            line += 1;
            column = 0;
            continue;
        }
        column += 1;
    } else offset = @intCast(text.len);

    // Find beginning of substring
    var start = offset;
    while (start > 0) : (start -= 1) {
        switch (text[@intCast(start - 1)]) {
            '\n', ' ', '\t' => break,
            else => {},
        }
    }

    // Find out if we are inside a comment
    var cursor: usize = @intCast(start);
    while (text[cursor] != '\n' and cursor > 0) : (cursor -= 1) {
        if (text[cursor - 1] == '#') return;
    }

    const kind: lsp.CompletionItemKind = switch (text[@intCast(start)]) {
        arch.instr.prefix.keyword => blk: {
            start += 1;
            break :blk .Keyword;
        },
        // We don't offer completion for labels, literals or strings
        arch.instr.prefix.label,
        arch.instr.prefix.integer,
        arch.instr.prefix.float,
        '"',
        => return,
        else => .Method,
    };

    // zig fmt: off
    const substr = text[
        @as(usize, @intCast(start))..@as(usize, @intCast(offset))
    ];
    // zig fmt: on

    std.log.info("Considering substring \"{s}\" for completion", .{substr});

    switch (kind) {
        .Keyword => {
            for (std.enums.values(asm_.Token.Keyword)) |kw| {
                if (std.mem.startsWith(u8, @tagName(kw), substr)) {
                    try list.append(.{
                        .label = @tagName(kw),
                        .kind = @intFromEnum(kind),
                    });
                }
            }
        },
        .Method => {
            for (std.enums.values(arch.instr.Instruction)) |instr| {
                if (std.mem.startsWith(u8, @tagName(instr), substr)) {
                    try list.append(.{
                        .label = @tagName(instr),
                        .kind = @intFromEnum(kind),
                    });
                }
            }
        },
        else => unreachable,
    }
}
