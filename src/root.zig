const std = @import("std");

test {
    _ = @import("tests.zig");
}

pub const world = @import("world.zig");
pub const World = world.World;
pub const Entity = world.Entity;
