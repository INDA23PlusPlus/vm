const std = @import("std");
const arch = @import("arch");
const ExecContext = @import("exec_context.zig").ExecContext;

const Self = @This();

code: []const u8,
fn_ptr: *fn (*ExecContext) callconv(.C) i64,

pub fn init(image: []const u8) !Self {
    const size = image.len;
    const addr = std.os.linux.mmap(null, size, std.os.linux.PROT.READ | std.os.linux.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr = @as(?[*]u8, @ptrFromInt(addr)) orelse return error.OutOfMemory;
    errdefer _ = std.os.linux.munmap(ptr, size);

    @memcpy(ptr, image);

    if (std.os.linux.mprotect(ptr, size, std.os.linux.PROT.READ | std.os.linux.PROT.EXEC) != 0) {
        return error.AccessDenied;
    }

    return .{ .code = ptr[0..size], .fn_ptr = @ptrCast(ptr) };
}

pub fn deinit(self: *Self) void {
    _ = std.os.linux.munmap(@ptrCast(self.code), self.code.len);
}

pub fn execute(self: *Self) !i64 {
    var exec_common = ExecContext.Common{};
    var exec_ctxt = ExecContext.init(&exec_common);
    defer exec_ctxt.deinit();

    const ret = self.fn_ptr(&exec_ctxt);

    return exec_ctxt.common.err orelse ret;
}
