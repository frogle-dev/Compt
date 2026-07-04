const std = @import("std");

const compt = @import("Compt");

// COMPONENTS
const Position = struct {
    x: u32 = 0,
    y: u32 = 0,
};
const Velocity = struct {
    x: u32 = 0,
    y: u32 = 0,
};
const Health = struct {
    max: u16 = 100,
    val: u16 = 100,
};
const Defense = struct {
    val: u16 = 0,
};
const Attack = struct {
    val: u16 = 0,
};

// ENTITIES
const Player = struct {
    position: Position,
    velocity: Velocity,
    health: Health,
    attack: Attack,
};
const Tree = struct {
    position: Position,
    health: Health,
};
const UI_Element = struct {
    position: Position,
};

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);

    // const gpa = debug_allocator.allocator();
    // const gpa = switch (@import("builtin").mode) {
    //     .Debug, .ReleaseSafe => {
    //         debug_allocator.allocator();
    //     },
    //     .ReleaseFast, .ReleaseSmall => std.heap.c_allocator,
    // };

    std.debug.print("-.-", .{});
}
