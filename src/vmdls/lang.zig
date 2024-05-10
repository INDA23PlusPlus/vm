//!
//! Language tags.
//!

const utils = @import("utils.zig");

pub const Tag = enum {
    /// Melancolang source code
    melancolang,
    /// Assembly for VeMod
    vemod,
    /// Blue source code
    blue,

    pub const map = utils.TagNameMap(@This());
};
