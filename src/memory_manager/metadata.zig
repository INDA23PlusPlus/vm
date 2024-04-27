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
            if (refcount != 0 and std.debug.runtime_safety) {
                std.debug.panic("deinit with non-zero refcount: {}", .{refcount});
            }
            self.deinit_unchecked();
        }

        pub fn deinit_unchecked(self: *Self) void {
            _ = self;
        }

        pub fn increment(self: *Self) void {
            // @atomic* builtins only take pointers to ints such as `u8` `u16` `i32` etc
            // therefore cast Self pointer to a pointer compatible with the builtins
            const ptr: *SelfIntType = @ptrCast(self);

            // modify count
            const res = @atomicRmw(SelfIntType, ptr, .Add, 1, .monotonic);

            // cast result back to `Self`
            const self_before: Self = @bitCast(res);

            // count cant go above `maxInt`, so when we added one it overflowed into the bits for `MarkType` and invalidated `self.mark`
            if (self_before.count == std.math.maxInt(CountType) and std.debug.runtime_safety) {
                std.debug.panic("incremented maximal refcount, overflowed self.mark", .{});
            }
        }

        pub fn decrement(self: *Self) void {
            // @atomic* builtins only take pointers to ints such as `u8` `u16` `i32` etc
            // therefore cast Self pointer to a pointer compatible with the builtins
            const ptr: *SelfIntType = @ptrCast(self);

            // modify count
            const res = @atomicRmw(SelfIntType, ptr, .Sub, 1, .monotonic);

            // cast result back to `Self`
            const self_before: Self = @bitCast(res);

            // count can't go below zero, so when we subtracted one it overflowed into the bits for `MarkType` and invalidated `self.mark`
            if (self_before.count == 0 and std.debug.runtime_safety) {
                std.debug.panic("decremented zero refcount, overflowed self.mark ", .{});
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
