pub const APITypes = @import("APITypes.zig");
pub const MemoryManager = @import("MemoryManager.zig");

test {
    _ = @import("types.zig");
    _ = @import("APITypes.zig");
}

comptime {
    _ = @import("MemoryManager.zig").alloc_struct;
    _ = @import("MemoryManager.zig").alloc_list;
}
