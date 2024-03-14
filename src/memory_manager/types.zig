const RefCount = @import("RefCount.zig");

pub const List = struct {
    items: []Types,

    refcount: RefCount, // stack references
};

pub const Object = struct {
    // TODO: add an actual internal representation, some kind of hashmap

    refcount: RefCount, // stack references
};

pub const Types = packed union {
    unit: @TypeOf(.{}),
    int: i64,
    float: f64,
    list: List,
    object: Object,
};
