const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const network_module = b.dependency("network", .{ .target = target, .optimize = optimize }).module("network");

    const module = b.addModule("raknet", .{
        .source_file = .{ .path = "src/raknet.zig" },
        .dependencies = &.{
            .{ .name = "network", .module = network_module },
        },
    });

    const executable = b.addExecutable(.{
        .name = "raknet_example",
        .root_source_file = .{ .path = "examples/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    executable.addModule("raknet", module);
    executable.addModule("network", network_module);
    const artifact = b.addInstallArtifact(executable);
    const executable_step = b.step("example", "Builds the main example");
    executable_step.dependOn(&artifact.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    const test_artifact = b.addRunArtifact(main_tests);
    main_tests.addModule("raknet", module);
    main_tests.addModule("network", network_module);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
