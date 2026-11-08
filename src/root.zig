const std = @import("std");

test {
    _ = @import("tests.zig");
}

pub const reg = @import("registry.zig");
pub const Registry = reg.Registry;
pub const EntityID = reg.EntityID;
