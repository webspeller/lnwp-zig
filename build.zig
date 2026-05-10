const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lnwp_mod = b.addModule("lnwp", .{
        .root_source_file = b.path("src/lnwp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "lnwp",
        .root_module = lnwp_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lnwp", .module = lnwp_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "lnwp-inspect",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const api_mod = b.createModule(.{
        .root_source_file = b.path("src/api_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lnwp", .module = lnwp_mod },
        },
    });
    api_mod.addEmbedPath(b.path("docs"));

    const api_exe = b.addExecutable(.{
        .name = "lnwp-api",
        .root_module = api_mod,
    });
    b.installArtifact(api_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run lnwp-inspect");
    run_step.dependOn(&run_cmd.step);

    const run_api_cmd = b.addRunArtifact(api_exe);
    run_api_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_api_cmd.addArgs(args);
    }

    const run_api_step = b.step("api", "Run lnwp-api HTTP server");
    run_api_step.dependOn(&run_api_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = lnwp_mod,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run protocol library tests");
    test_step.dependOn(&run_lib_tests.step);
}
