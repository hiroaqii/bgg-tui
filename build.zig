const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml_dep = b.dependency("xml", .{
        .target = target,
        .optimize = optimize,
    });
    const chasen_dep = b.dependency("chasen", .{
        .target = target,
        .optimize = optimize,
    });
    const chasen_ui_dep = b.dependency("chasen_ui", .{
        .target = target,
        .optimize = optimize,
    });
    const chasen_anim_dep = b.dependency("chasen_anim", .{
        .target = target,
        .optimize = optimize,
    });
    const chasen_graphics_dep = b.dependency("chasen_graphics", .{
        .target = target,
        .optimize = optimize,
    });

    const version = "0.4.0-dev";
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);

    const mod = b.addModule("bgg_tui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "build_options", .module = build_options.createModule() },
            .{ .name = "xml", .module = xml_dep.module("xml") },
            .{ .name = "chasen", .module = chasen_dep.module("chasen") },
            .{ .name = "chasen_ui", .module = chasen_ui_dep.module("chasen_ui") },
            .{ .name = "chasen_anim", .module = chasen_anim_dep.module("chasen_anim") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "bgg-tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "bgg_tui", .module = mod },
                .{ .name = "chasen", .module = chasen_dep.module("chasen") },
                .{ .name = "chasen_graphics_chasen", .module = chasen_graphics_dep.module("chasen_graphics_chasen") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run bgg-tui");
    run_step.dependOn(&run_exe.step);

    const live_check_exe = b.addExecutable(.{
        .name = "bgg-tui-live-api-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/live_check.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "bgg_tui", .module = mod },
            },
        }),
    });
    const run_live_check = b.addRunArtifact(live_check_exe);

    const live_check_step = b.step("check-live-api", "Run a manual BGG API check using the configured token");
    live_check_step.dependOn(&run_live_check.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
