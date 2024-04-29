//!
//! Language tags.
//!

const utils = @import("utils.zig");

pub const Tag = enum {
    /// Melancolang source code
    melancolang,
    /// Assembly for VeMod
    vemod,

    pub const map = utils.TagNameMap(@This());
};
