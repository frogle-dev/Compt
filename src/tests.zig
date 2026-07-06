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

test "spawn" {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var registry = try compt.Registry(.{ Player, Tree, UI_Element }).init(gpa);
    defer registry.deinit();

    const player: Player = .{
        .position = .{ .x = 0, .y = 10 },
        .velocity = .{ .x = 0, .y = 10 },
        .health = .{ .max = 100, .val = 100 },
        .attack = .{ .val = 15 },
    };
    const tree: Tree = .{
        .position = .{ .x = 0, .y = 0 },
        .health = .{ .max = 50, .val = 50 },
    };
    const ui: UI_Element = .{ .position = .{ .x = 0, .y = 100 } };

    const id0 = try registry.spawn(player);
    const id1 = try registry.spawn(tree);
    const id2 = try registry.spawn(tree);
    const id3 = try registry.spawn(ui);

    // IDs are sequential
    try std.testing.expectEqual(0, id0);
    try std.testing.expectEqual(1, id1);
    try std.testing.expectEqual(2, id2);
    try std.testing.expectEqual(3, id3);

    // correct storage lengths
    try std.testing.expectEqual(1, registry.templates.@"0".len); // 1 player
    try std.testing.expectEqual(2, registry.templates.@"1".len); // 2 trees
    try std.testing.expectEqual(1, registry.templates.@"2".len); // 1 ui element

    // entity_positions recorded correctly
    try std.testing.expectEqual(0, registry.entity_positions.get(id0).?.template_idx);
    try std.testing.expectEqual(0, registry.entity_positions.get(id0).?.entity_idx);
    try std.testing.expectEqual(1, registry.entity_positions.get(id1).?.template_idx);
    try std.testing.expectEqual(1, registry.entity_positions.get(id2).?.template_idx);
    try std.testing.expectEqual(1, registry.entity_positions.get(id2).?.entity_idx);

    // data stored correctly
    const stored_player = registry.templates.@"0".get(0);
    try std.testing.expectEqual(0, stored_player.position.x);
    try std.testing.expectEqual(10, stored_player.position.y);
    try std.testing.expectEqual(100, stored_player.health.val);
    // try std.testing.expectEqual(true, stored_player.enabled);
}

test "query" {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var registry = try compt.Registry(.{ Player, Tree, UI_Element }).init(gpa);
    defer registry.deinit();

    const player: Player = .{
        .position = .{ .x = 0, .y = 10 },
        .velocity = .{ .x = 0, .y = 10 },
        .health = .{ .max = 100, .val = 100 },
        .attack = .{ .val = 15 },
    };
    const tree: Tree = .{
        .position = .{ .x = 0, .y = 0 },
        .health = .{ .max = 50, .val = 50 },
    };
    const ui: UI_Element = .{ .position = .{ .x = 0, .y = 100 } };

    const id0 = try registry.spawn(player);
    const id1 = try registry.spawn(tree);
    const id2 = try registry.spawn(tree);
    const id3 = try registry.spawn(ui);
    _ = id0;
    _ = id1;
    _ = id2;
    _ = id3;

    var q1 = try registry.query(.{Position}, .{}, .{Velocity});
    defer q1.deinit(gpa);
    // std.debug.print("{any}\n", .{q1.items(.Position)});
    // std.debug.print("{any}\n", .{q1.items(.Velocity)});
    try std.testing.expectEqual(4, q1.queryResultCount());
    try std.testing.expectEqual(4, q1.getHasComponents(Position).len);
    try std.testing.expectEqual(4, q1.getMaybeComponents(Velocity).len);

    var q2 = try registry.query(.{Position}, .{}, .{Health});
    defer q2.deinit(gpa);
    // std.debug.print("{any}\n", .{q2.items(.Position)});
    // std.debug.print("{any}\n", .{q2.items(.Health)});
    try std.testing.expectEqual(4, q2.queryResultCount());
    try std.testing.expectEqual(4, q2.getHasComponents(Position).len);
    try std.testing.expectEqual(4, q2.getMaybeComponents(Health).len);

    var q3 = try registry.query(.{Position}, .{}, .{});
    defer q3.deinit(gpa);
    // std.debug.print("{any}\n", .{q3.items(.Position)});
    try std.testing.expectEqual(4, q3.queryResultCount());
    try std.testing.expectEqual(4, q3.getHasComponents(Position).len);

    var q4 = try registry.query(.{Position}, .{Attack}, .{Health});
    defer q4.deinit(gpa);
    // std.debug.print("{any}\n", .{q4.items(.Position)});
    // std.debug.print("{any}\n", .{q4.items(.Health)});
    try std.testing.expectEqual(3, q4.queryResultCount());
    try std.testing.expectEqual(3, q4.getHasComponents(Position).len);
    try std.testing.expectEqual(3, q4.getMaybeComponents(Health).len);
}

test "system" {}
