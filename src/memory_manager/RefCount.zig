//!
//! Simple reference counting for keeping track of which Objects and Lists are accessible from the stack
//!

const std = @import("std");
const Self = @This();
count: u32,

pub fn init() Self {
    return .{ .count = 1 };
}

pub fn deinit(self: *Self) void {
    const refcount = self.get();
    if (refcount != 0) {
        std.debug.panic("deinit with non-zero refcount: {}", .{refcount});
    }
    self.deinit_unchecked();
}

pub fn deinit_unchecked(self: *Self) void {
    _ = self;
}

// returns old value
pub fn increment(self: *Self) u32 {
    return @atomicRmw(u32, &self.count, .Add, 1, .monotonic);
}

// returns old value
pub fn decrement(self: *Self) u32 {
    const res = @atomicRmw(u32, &self.count, .Sub, 1, .monotonic);
    if (std.debug.runtime_safety and res == 0) {
        std.debug.panic("decremented zero refcount", .{});
    }
    return res;
}

pub fn get(self: *const Self) u32 {
    return @atomicLoad(u32, &self.count, .monotonic);
}

test "increment/decrement" {
    var cnt: Self = init();
    defer {
        // refcount starts at 1, so for this test we need to decrement
        // to get the refcount to zero before calling deinit.
        _ = cnt.decrement();
        cnt.deinit();
    }

    const incr_decr = struct {
        fn incr_decr(counter: *Self, amount: usize) void {
            for (0..amount) |_| {
                _ = counter.increment();
                std.Thread.yield() catch unreachable;
                _ = counter.decrement();
            }
        }
    }.incr_decr;

    // just do a bunch of increments and decrements

    var threads: [1000]std.Thread = undefined;

    for (0..1000) |i| {
        threads[i] = try std.Thread.spawn(.{}, incr_decr, .{ &cnt, 1000 });
    }
    for (0..1000) |i| {
        threads[i].join();
    }

    try std.testing.expectEqual(@as(u32, 1), cnt.get());
}
