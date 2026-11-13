const std = @import("std");

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expect = testing.expect;

const compt = @import("root.zig");

const Position = struct { x: u32 = 0, y: u32 = 0 };
const Velocity = struct { x: u32 = 0, y: u32 = 0 };
const Health = struct { max: u16 = 100, val: u16 = 100 };
const Defense = struct { val: u16 = 0 };
const Attack = struct { val: u16 = 0 };

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

const UI = struct {
    position: Position,
};

test "spawn" {
    const alcr = testing.allocator;

    var world = try compt.World(&.{ Player, Tree, UI }).init(alcr);
    defer world.deinit();

    const player = try world.spawn(Player{
        .position = .{ .x = 11, .y = 12 },
        .velocity = .{ .x = 13, .y = 14 },
        .health = .{ .max = 15, .val = 16 },
        .attack = .{ .val = 17 },
    });

    const tree1 = try world.spawn(Tree{
        .position = .{ .x = 21, .y = 22 },
        .health = .{ .max = 50, .val = 40 },
    });

    const tree2 = try world.spawn(Tree{
        .position = .{ .x = 31, .y = 32 },
        .health = .{ .max = 60, .val = 45 },
    });

    const ui = try world.spawn(UI{
        .position = .{ .x = 41, .y = 100 },
    });

    try expectEqual(0, player);
    try expectEqual(1, tree1);
    try expectEqual(2, tree2);
    try expectEqual(3, ui);

    try expectEqual(1, world.storage.@"0".len);
    try expectEqual(2, world.storage.@"1".len);
    try expectEqual(1, world.storage.@"2".len);

    try expectEqual(0, world.entity_locations.get(player).?.template_idx);
    try expectEqual(0, world.entity_locations.get(player).?.idx);
    try expectEqual(1, world.entity_locations.get(tree1).?.template_idx);
    try expectEqual(0, world.entity_locations.get(tree1).?.idx);
    try expectEqual(1, world.entity_locations.get(tree2).?.template_idx);
    try expectEqual(1, world.entity_locations.get(tree2).?.idx);
    try expectEqual(2, world.entity_locations.get(ui).?.template_idx);
    try expectEqual(0, world.entity_locations.get(ui).?.idx);

    const stored_player = world.storage.@"0".get(0);
    try expectEqual(11, stored_player.position.x);
    try expectEqual(12, stored_player.position.y);
    try expectEqual(13, stored_player.velocity.x);
    try expectEqual(14, stored_player.velocity.y);
    try expectEqual(15, stored_player.health.max);
    try expectEqual(16, stored_player.health.val);
    try expectEqual(17, stored_player.attack.val);

    const stored_tree1 = world.storage.@"1".get(0);
    try expectEqual(21, stored_tree1.position.x);
    try expectEqual(40, stored_tree1.health.val);

    const stored_tree2 = world.storage.@"1".get(1);
    try expectEqual(31, stored_tree2.position.x);
    try expectEqual(45, stored_tree2.health.val);

    const stored_ui = world.storage.@"2".get(0);
    try expectEqual(41, stored_ui.position.x);
    try expectEqual(100, stored_ui.position.y);

    try expect(world.isCorrectLengths());
}

// test "query" {
//     const alcr = testing.allocator;
//
//     var registry = try compt.Registry(.{ Player, Tree, UI_Element }).init(alcr);
//     defer registry.deinit();
//
//     const player: Player = .{
//         .position = .{ .x = 0, .y = 10 },
//         .velocity = .{ .x = 0, .y = 10 },
//         .health = .{ .max = 100, .val = 100 },
//         .attack = .{ .val = 15 },
//     };
//     const tree: Tree = .{
//         .position = .{ .x = 0, .y = 0 },
//         .health = .{ .max = 50, .val = 50 },
//     };
//     const ui: UI_Element = .{ .position = .{ .x = 0, .y = 100 } };
//
//     const id0 = try registry.spawn(player);
//     const id1 = try registry.spawn(tree);
//     const id2 = try registry.spawn(tree);
//     const id3 = try registry.spawn(ui);
//     _ = id0;
//     _ = id1;
//     _ = id2;
//     _ = id3;
//
//     var q1 = try registry.query(.{Position}, .{}, .{Velocity});
//     defer q1.deinit(alcr);
//     // std.debug.print("{any}\n", .{q1.items(.Position)});
//     // std.debug.print("{any}\n", .{q1.items(.Velocity)});
//     try testing.expectEqual(4, q1.queryResultCount());
//     try testing.expectEqual(4, q1.getComponents(Position).len);
//     try testing.expectEqual(4, q1.getComponents(Velocity).len);
//
//     var q2 = try registry.query(.{Position}, .{}, .{Health});
//     defer q2.deinit(alcr);
//     // std.debug.print("{any}\n", .{q2.items(.Position)});
//     // std.debug.print("{any}\n", .{q2.items(.Health)});
//     try testing.expectEqual(4, q2.queryResultCount());
//     try testing.expectEqual(4, q2.getComponents(Position).len);
//     try testing.expectEqual(4, q2.getComponents(Health).len);
//
//     var q3 = try registry.query(.{Position}, .{}, .{});
//     defer q3.deinit(alcr);
//     // std.debug.print("{any}\n", .{q3.items(.Position)});
//     try testing.expectEqual(4, q3.queryResultCount());
//     try testing.expectEqual(4, q3.getComponents(Position).len);
//
//     var q4 = try registry.query(.{Position}, .{Attack}, .{Health});
//     defer q4.deinit(alcr);
//     // std.debug.print("{any}\n", .{q4.items(.Position)});
//     // std.debug.print("{any}\n", .{q4.items(.Health)});
//     try testing.expectEqual(3, q4.queryResultCount());
//     try testing.expectEqual(3, q4.getComponents(Position).len);
//     try testing.expectEqual(3, q4.getComponents(Health).len);
// }
//
// test "enable/disable components" {}
//
// test "system" {}
