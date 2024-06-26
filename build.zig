const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const network_module = b.dependency("network", .{ .target = target, .optimize = optimize }).module("network");

    const module = b.addModule("raknet", .{ .root_source_file = b.path("src/raknet.zig") });
    module.addImport("network", network_module);

    const server_example = b.addExecutable(.{
        .name = "server_example",
        .root_source_file = b.path("examples/server_example.zig"),
        .target = target,
        .optimize = optimize,
    });

    server_example.root_module.addImport("raknet", module);
    server_example.root_module.addImport("network", network_module);
    const server_artifact = b.addRunArtifact(server_example);
    const server_step = b.step("server_example", "Runs the server example");
    server_step.dependOn(&server_artifact.step);

    const client_example = b.addExecutable(.{
        .name = "server_example",
        .root_source_file = b.path("examples/client_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_example.root_module.addImport("raknet", module);
    client_example.root_module.addImport("network", network_module);
    const client_artifact = b.addRunArtifact(client_example);
    const client_step = b.step("client_example", "Runs the client example");
    client_step.dependOn(&client_artifact.step);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_artifact = b.addRunArtifact(main_tests);
    main_tests.root_module.addImport("raknet", module);
    main_tests.root_module.addImport("network", network_module);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_artifact.step);
}
