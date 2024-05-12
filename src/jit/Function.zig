const std = @import("std");
const arch = @import("arch");
const ExecContext = @import("exec_context.zig").ExecContext;

const Self = @This();

alloc: std.mem.Allocator,
code: []const u8,
pc_map: ?[]const usize,
fn_ptr: *fn (*ExecContext) callconv(.C) i64,
rterror: ?arch.err.RtError = null,

pub fn init(alloc: std.mem.Allocator, image: []const u8, pc_map: ?[]const usize) !Self {
    const size = image.len;
    const addr = std.os.linux.mmap(null, size, std.os.linux.PROT.READ | std.os.linux.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr = @as(?[*]u8, @ptrFromInt(addr)) orelse return error.OutOfMemory;
    errdefer _ = std.os.linux.munmap(ptr, size);

    @memcpy(ptr, image);

    if (std.os.linux.mprotect(ptr, size, std.os.linux.PROT.READ | std.os.linux.PROT.EXEC) != 0) {
        return error.AccessDenied;
    }

    return .{ .alloc = alloc, .code = ptr[0..size], .pc_map = pc_map, .fn_ptr = @ptrCast(ptr) };
}

pub fn deinit(self: *Self) void {
    if (self.pc_map) |pc_map| {
        self.alloc.free(pc_map);
    }
    _ = std.os.linux.munmap(@ptrCast(self.code), self.code.len);
}

fn map_pc(self: *const Self, err_pc: usize) ?usize {
    const code_addr = @intFromPtr(@as([*]const u8, @ptrCast(self.code)));

    if (err_pc < code_addr) {
        return null;
    }

    if (self.pc_map) |pc_map| {
        const offset = err_pc - code_addr;
        var vm_pc: usize = 0;

        if (pc_map.len == 0 or offset < pc_map[0] or offset >= pc_map[pc_map.len - 1]) {
            return null;
        }

        while (pc_map[vm_pc + 1] < offset) {
            vm_pc += 1;
        }

        return vm_pc;
    } else {
        return null;
    }
}

pub fn execute(self: *Self) !i64 {
    var exec_common = ExecContext.Common{};
    var exec_ctxt = ExecContext.init(&exec_common);
    defer exec_ctxt.deinit();

    const ret = self.fn_ptr(&exec_ctxt);

    self.rterror = exec_common.rterror;

    if (self.rterror) |*rterror| {
        rterror.pc = self.map_pc(exec_ctxt.err_pc);
    }

    return exec_ctxt.common.err orelse ret;
}
