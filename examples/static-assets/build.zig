const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimzie = b.standardOptimizeOption(.{});

    const mod = b.addModule("zws", .{
        .root_source_file = b.path("../../src/root.zig"),
        .target = target,
        .optimize = optimzie,
    });

    const exe = b.addExecutable(.{
        .name = "static_assets",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimzie,
            .imports = &.{
                .{ .name = "zws", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the static_assets example");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
