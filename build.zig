const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dedalus = b.dependency("dedalus", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "cozroe",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(dedalus.artifact("wolfssl"));
    exe.addModule("dedalus", dedalus.module("dedalus"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const start_server = b.step("run", "Start the server");
    start_server.dependOn(&run_exe.step);

    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    test_exe.linkLibrary(dedalus.artifact("wolfssl"));
    test_exe.addModule("dedalus", dedalus.module("dedalus"));

    const run_tests = b.addRunArtifact(test_exe);
    const start_tests = b.step("test", "Execute tests");
    start_tests.dependOn(&run_tests.step);
}
