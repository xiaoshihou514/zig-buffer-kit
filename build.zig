const std = @import("std");

pub const test_targets = [_]std.Target.Query{
    .{}, // native
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
};

pub fn build(b: *std.Build) void {
    const buildTarget = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // building
    const lib = b.addStaticLibrary(.{
        .name = "zig-buffer-kit",
        .root_source_file = b.path("src/lib.zig"),
        .target = buildTarget,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 0, .patch = 1 },
    });

    b.installArtifact(lib);

    // testing
    const test_step = b.step("test", "Run unit tests");
    const tests = [_][]const u8{
        "src/BOTree.zig",
        "src/utils.zig",
    };
    for (test_targets) |target| {
        for (tests) |unit_test| {
            const unit_tests = b.addTest(.{
                .root_source_file = b.path(unit_test),
                .target = b.resolveTargetQuery(target),
            });

            const run_unit_tests = b.addRunArtifact(unit_tests);
            run_unit_tests.skip_foreign_checks = true;
            test_step.dependOn(&run_unit_tests.step);
        }
    }
}
