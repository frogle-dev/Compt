const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compt = b.addModule("Compt", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const compt_tests = b.addTest(.{
        .root_module = compt,
    });

    const run_compt_tests = b.addRunArtifact(compt_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_compt_tests.step);
}
