const std = @import("std");

pub fn build(b: *std.Build) !void {
    const ndk_version = "29.0.14206865";
    const ndk_api = "35";
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("ncore", .{
        .root_source_file = b.path("src/root.zig"),

        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "ncore",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "ncore", .module = mod },
            },
        }),
    });

    const lib = b.addLibrary(.{
        .name = "ncore",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (target.result.abi == .android) {
        const allocator = b.allocator;
        const arch_name = @tagName(target.result.cpu.arch);

        const triple = b.fmt("{s}-linux-android/", .{arch_name});

        const path = try std.process.getEnvVarOwned(allocator, "ANDROID_HOME");
        const sys_root = b.pathJoin(&.{ path, "ndk/", ndk_version, "toolchains/llvm/prebuilt/linux-x86_64/sysroot" });
        const include = b.pathJoin(&.{ sys_root, "/usr/include" });
        const libpath = b.pathJoin(&.{ sys_root, "/usr/lib/", triple, ndk_api });
        exe.addIncludePath(.{ .cwd_relative = include });
        exe.addLibraryPath(.{ .cwd_relative = libpath });
        mod.addIncludePath(.{ .cwd_relative = include });
        mod.addLibraryPath(.{ .cwd_relative = libpath });
        lib.addIncludePath(.{ .cwd_relative = include });
        lib.addLibraryPath(.{ .cwd_relative = libpath });
        exe.linkSystemLibrary("log");
    }

    b.installArtifact(exe);
    b.installArtifact(lib);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
