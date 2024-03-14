const std = @import("std");
// TODO: maybe we don't need SeqCst for all the operations?
const Self = @This();
count: u32,

pub fn init() Self {
    return .{ .count = 1 };
}

pub fn deinit(self: *Self) void {
    _ = self.decrement();
}

// returns old value
pub fn increment(self: *Self) u32 {
    return @atomicRmw(u32, &self.count, .Add, 1, .SeqCst);
}

// returns old value
pub fn decrement(self: *Self) u32 {

    // TODO: relax these memory orders a bit
    const LoadOrder = .SeqCst; // this can probably be .Unordered
    const SuccessOrder = .SeqCst; // this can probably be .Monotonic
    const FailOrder = .SeqCst; // this can probably be .Monotonic

    var res: u32 = @atomicLoad(u32, &self.count, LoadOrder);
    // if res is zero we cant decrement, so load again
    // if the compare exchange failed try again, but since someone changed the value
    while (true) {
        if (res == 0) { // cant decrement below zero
            res = @atomicLoad(u32, &self.count, LoadOrder);
            std.Thread.yield() catch {}; // if this errors, it doesnt really matter anyways
        } else if (@cmpxchgWeak(u32, &self.count, res, res - 1, SuccessOrder, FailOrder)) |e| { // if the compare
            res = e;
        } else {
            return res;
        }
    }
}

pub fn get(self: *const Self) u32 {
    return @atomicLoad(u32, &self.count, .SeqCst);
}

test "increment/decrement" {
    var cnt: Self = init();
    defer cnt.deinit();

    const incr = struct {
        fn incr(counter: *Self, amount: usize) void {
            for (0..amount) |_| {
                _ = counter.increment();
                std.Thread.yield() catch unreachable;
            }
        }
    }.incr;

    const decr = struct {
        fn decr(counter: *Self, amount: usize) void {
            for (0..amount) |_| {
                _ = counter.decrement();
                std.Thread.yield() catch unreachable;
            }
        }
    }.decr;

    // just do a bunch of increments and decrements
    var t2 = try std.Thread.spawn(.{ .allocator = std.testing.allocator }, decr, .{ &cnt, 10000 });
    var t1 = try std.Thread.spawn(.{ .allocator = std.testing.allocator }, incr, .{ &cnt, 10000 });

    t1.join();
    t2.join();

    try std.testing.expectEqual(@as(u32, 1), cnt.get());
}
