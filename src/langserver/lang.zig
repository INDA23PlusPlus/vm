//!
//! Language tags.
//!

const utils = @import("utils.zig");

pub const Tag = enum {
    /// Melancolang source code
    mcl,
    /// Assembly for VeMod
    vmd,

    pub const map = utils.TagNameMap(@This());
};
