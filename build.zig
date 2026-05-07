const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Interpreter (default build) ----
    const exe = b.addExecutable(.{
        .name = "joya",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Conditionally include C source for ucontext backend (Linux/macOS)
    const tag = target.result.os.tag;
    if (tag == .linux or tag == .macos) {
        exe.addCSourceFile(.{
            .file = b.path("src/fiber_ucontext.c"),
            .flags = &.{"-D_XOPEN_SOURCE"},
        });
        exe.linkLibC();
    }

    // LLVM linking (compiler mode)
    linkLLVM(exe, target);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Joya interpreter");
    run_step.dependOn(&run_cmd.step);
}

fn linkLLVM(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const tag = target.result.os.tag;

    if (tag == .windows) {
        // Windows: link against LLVM-C.lib from standard install path
        exe.addIncludePath(.{ .cwd_relative = "C:\\Program Files\\LLVM\\include" });
        exe.addLibraryPath(.{ .cwd_relative = "C:\\Program Files\\LLVM\\lib" });
        exe.linkSystemLibrary("LLVM-C");
        exe.linkLibC();
    } else if (tag == .linux) {
        // Linux: use llvm-config or standard paths
        exe.linkSystemLibrary("LLVM");
        exe.linkLibC();
    } else if (tag == .macos) {
        // macOS: use Homebrew LLVM or system
        exe.linkSystemLibrary("LLVM");
        exe.linkLibC();
    }
}
