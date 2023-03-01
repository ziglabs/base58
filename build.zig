const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

   // builds the library as a static library
    {
    const lib = b.addStaticLibrary("base58", "src/base58.zig");
    lib.setBuildMode(mode);
    lib.install();
    }

    // builds and runs the tests
    {
    const base58_tests = b.addTest("src/base58.zig");
    base58_tests.setBuildMode(mode);
    base58_tests.use_stage1 = true;
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&base58_tests.step);
    }
}
