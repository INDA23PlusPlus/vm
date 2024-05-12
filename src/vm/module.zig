pub const VMContext = @import("VMContext.zig");
pub const interpreter = @import("interpreter.zig");

test {
    _ = @import("VMContext.zig");
    _ = @import("interpreter.zig");
}
