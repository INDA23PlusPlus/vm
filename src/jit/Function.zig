const std = @import("std");
const arch = @import("arch");
const ExecContext = @import("ExecContext.zig");

const Self = @This();

alloc: std.mem.Allocator,
code: []const u8,
pc_map: ?[]const usize,
rterror: ?arch.err.RtError = null,
write_ctxt: *const anyopaque = undefined,
write_fn: ?*const fn (*const anyopaque, []const u8) anyerror!usize = null,

pub fn init(alloc: std.mem.Allocator, image: []const u8, pc_map: ?[]const usize) !Self {
    const size = image.len;
    const addr = std.os.linux.mmap(null, size, std.os.linux.PROT.READ | std.os.linux.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
    const ptr = @as(?[*]u8, @ptrFromInt(addr)) orelse return error.OutOfMemory;
    errdefer _ = std.os.linux.munmap(ptr, size);

    @memcpy(ptr, image);

    if (std.os.linux.mprotect(ptr, size, std.os.linux.PROT.READ | std.os.linux.PROT.EXEC) != 0) {
        return error.AccessDenied;
    }

    return .{ .alloc = alloc, .code = ptr[0..size], .pc_map = pc_map };
}

pub fn deinit(self: *Self) void {
    if (self.pc_map) |pc_map| {
        self.alloc.free(pc_map);
    }
    _ = std.os.linux.munmap(@ptrCast(self.code), self.code.len);
}

pub fn set_writer(self: *Self, writer: anytype) void {
    self.write_ctxt = writer;
    self.write_fn = struct {
        fn write(write_ctxt: *const anyopaque, bytes: []const u8) anyerror!usize {
            const typed_ctxt: @TypeOf(writer) = @alignCast(@ptrCast(write_ctxt));
            return typed_ctxt.write(bytes);
        }
    }.write;
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

        while (pc_map[vm_pc] == 0 or (pc_map[vm_pc + 1] != 0 and pc_map[vm_pc + 1] < offset)) {
            vm_pc += 1;
        }

        return vm_pc;
    } else {
        return null;
    }
}

pub fn execute(self: *Self, globals: ?*anyopaque) !i64 {
    return self.execute_as(globals, fn () i64, .{});
}

pub fn execute_as(self: *Self, globals: ?*anyopaque, fn_type: type, args: anytype) @Type(std.builtin.Type{
    .ErrorUnion = .{
        .error_set = anyerror,
        .payload = @typeInfo(fn_type).Fn.return_type.?,
    },
}) {
    comptime var fn_typeinfo = @typeInfo(fn_type);
    fn_typeinfo.Fn.calling_convention = .C;
    fn_typeinfo.Fn.params = [_]std.builtin.Type.Fn.Param{.{ .is_generic = false, .is_noalias = false, .type = *ExecContext }} ++ fn_typeinfo.Fn.params;

    comptime var fn_ptr_typeinfo = @typeInfo(*const fn (*ExecContext) callconv(.C) i64);
    fn_ptr_typeinfo.Pointer.child = @Type(fn_typeinfo);

    var exec_ctxt = ExecContext.init();
    defer exec_ctxt.deinit();

    exec_ctxt.gp = @intFromPtr(globals);

    if (self.write_fn) |write_fn| {
        exec_ctxt.write_ctxt = self.write_ctxt;
        exec_ctxt.write_fn = write_fn;
    }

    const ret = @call(.auto, @as(@Type(fn_ptr_typeinfo), @ptrCast(self.code)), .{&exec_ctxt} ++ args);

    self.rterror = exec_ctxt.rterror;

    if (self.rterror) |*rterror| {
        rterror.pc = self.map_pc(exec_ctxt.err_pc);
    }

    return exec_ctxt.err orelse ret;
}

pub fn execute_sub(self: *Self, pc: usize, globals: ?*anyopaque, args: []const i64) !i64 {
    if (self.pc_map == null or self.pc_map.?[pc] == 0) {
        return error.NotCompiled;
    } else {
        return self.execute_as(globals, fn ([*]const i64, usize, usize) i64, .{ args.ptr, args.len, @intFromPtr(self.code.ptr) + self.pc_map.?[pc] });
    }
}
