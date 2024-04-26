//!
//! Simple reference counting for keeping track of which Objects and Lists are accessible from the stack
//!

pub fn Metadata(comptime CountType: type, comptime MarkType: type) type {
    return packed struct {
        const std = @import("std");
        const Self = @This();
        count: CountType,
        mark: MarkType,

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
            // Since we cannot create a pointer to a u15, we need to
            // perform the addition on the entire metadata packed struct.
            // Therefore, reinterpret cast to u16 and perform the addition
            // there and hope we don't overflow to the mark bit.
            const ptr: *const u16 = @ptrCast(self);
            _ = @atomicRmw(u16, @constCast(ptr), .Add, 1, .monotonic);
        }

        pub fn decrement(self: *Self) void {
            // See comment above.
            const ptr: *const u16 = @ptrCast(self);
            const res = @atomicRmw(u16, @constCast(ptr), .Sub, 1, .monotonic);
            if (std.debug.runtime_safety and res == 0) {
                std.debug.panic("decremented zero refcount", .{});
            }
        }

        pub fn get(self: *const Self) CountType {
            // Interpret self as u16 and read.
            // Then interpret back to u15 (which disgards mark bit)
            // very cursed.... VERY.
            const ptr: *const u16 = @ptrCast(self);
            const bits = @atomicLoad(u16, @constCast(ptr), .monotonic);
            const bits_ptr: *const CountType = @ptrCast(&bits);
            return bits_ptr.*;
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
