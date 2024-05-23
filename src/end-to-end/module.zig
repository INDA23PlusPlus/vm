//!
//! Vemod end-to-end testing
//!

const std = @import("std");
const testing = std.testing;
const process = std.process;
const mem = std.mem;
const ArrayList = std.ArrayList;
const vemod_path = @import("vemod").@"vemod-path";
const debug = std.debug;

test "simple arithmetic" {
    try case("1+2", "3", 0);
    try case("16*0.0625", "1", 0);
}

test "hailstone" {
    try case(@embedFile("hailstone.blue"), @embedFile("hailstone_out.txt"), 0);
}

test "mandelbrot" {
    try case(@embedFile("mandelbrot.blue"), @embedFile("mandelbrot_out.txt"), 0);
}

// ...
// More tests

fn case(
    input: []const u8,
    expected_output: []const u8,
    expected_return_code: u8,
) !void {
    var child = process.Child.init(&.{ vemod_path, "-r" }, testing.allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    try child.stdin.?.writer().writeAll(input);
    child.stdin.?.close();
    child.stdin = null;

    var collect_stdout = ArrayList(u8).init(testing.allocator);
    defer collect_stdout.deinit();
    var collect_stderr = ArrayList(u8).init(testing.allocator);
    defer collect_stderr.deinit();

    try child.collectOutput(
        &collect_stdout,
        &collect_stderr,
        std.math.maxInt(usize),
    );

    const term = child.wait() catch |e| {
        debug.panic(
            \\
            \\Error: unable to run {s}: {s}
            \\
            \\
        ,
            .{
                vemod_path,
                @errorName(e),
            },
        );
    };

    try testing.expectEqualSlices(
        u8,
        mem.trim(u8, expected_output, " \n"),
        mem.trim(u8, collect_stdout.items, " \n"),
    );

    switch (term) {
        .Exited => |c| try testing.expectEqual(c, expected_return_code),
        else => return error.ChildDidNotExit,
    }
}
