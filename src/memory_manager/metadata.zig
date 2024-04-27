//!
//! Simple reference counting for keeping track of which Objects and Lists are accessible from the stack
//!

pub fn Metadata(comptime CountType: type, comptime MarkType: type) type {
    return packed struct {
        const std = @import("std");
        const Self = @This();
        count: CountType,
        mark: MarkType,
        const CountBits = @bitSizeOf(CountType);
        const MarkBits = @bitSizeOf(MarkType);

        const SelfIntType = std.meta.Int(.unsigned, CountBits + MarkBits);

        pub fn init() Self {
            return .{ .count = 1, .mark = 0 };
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

        pub fn increment(self: *Self) void {
            const ptr: *SelfIntType = @ptrCast(self);
            const self_before: Self = @bitCast(@atomicRmw(SelfIntType, ptr, .Add, 1, .monotonic));
            if (self_before.count == std.math.maxInt(CountType) and std.debug.runtime_safety) {
                std.debug.panic("overflowed refcount", .{});
            }
        }

        pub fn decrement(self: *Self) void {
            const ptr: *SelfIntType = @ptrCast(self);
            const self_before: Self = @bitCast(@atomicRmw(SelfIntType, ptr, .Sub, 1, .monotonic));
            if (std.debug.runtime_safety and self_before.count == 0) {
                std.debug.panic("decremented zero refcount", .{});
            }
        }

        pub fn get(self: *const Self) CountType {
            const ptr: *const SelfIntType = @ptrCast(self);
            const self_deref: Self = @bitCast(@atomicLoad(SelfIntType, ptr, .monotonic));
            return self_deref.count;
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
    };
}
