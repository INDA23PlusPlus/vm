//!
//! Hover information for VeMod.
//!

const std = @import("std");
const arch = @import("arch");
const lsp = @import("../lsp.zig");
const asm_ = @import("asm");

pub fn getHoverInfo(
    text: []const u8,
    pos: lsp.Position,
    allocator: std.mem.Allocator,
) !?lsp.Hover {
    var line: i32 = 0;
    var col: i32 = 0;
    var offset: usize = undefined;

    for (0.., text) |i, c| {
        if (line == pos.line and col == pos.character) {
            offset = i;
            break;
        }
        if (c == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    } else offset = text.len;

    var errors = std.ArrayList(asm_.Error).init(allocator);
    defer errors.deinit();

    var scanner = asm_.Token.Scanner{
        .source = text,
        .errors = &errors,
    };

    const text_begin: usize = @intFromPtr(text.ptr);
    const hover_char = text_begin + offset;
    var hovered_token: ?asm_.Token = null;

    while (try scanner.next()) |token| {
        const tok_begin: usize = @intFromPtr(token.where.ptr);
        const tok_end = tok_begin + token.where.len;
        if (hover_char >= tok_begin and hover_char < tok_end) {
            switch (token.tag) {
                .instr => hovered_token = token,
                else => break,
            }
        }
    }

    if (hovered_token) |token| {
        const ref = try asm_.SourceRef.init(text, token.where);
        return .{
            .contents = arch.descr.text.get(token.tag.instr),
            .range = .{
                .start = .{
                    .line = @intCast(ref.line_num - 1),
                    .character = @intCast(ref.offset),
                },
                .end = .{
                    .line = @intCast(ref.line_num - 1),
                    .character = @intCast(ref.offset + ref.string.len),
                },
            },
        };
    } else {
        return null;
    }
}
