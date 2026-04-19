const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ndk_sysroot = b.option(
        []const u8,
        "ndk-sysroot",
        "Path to NDK sysroot (.../toolchains/llvm/prebuilt/linux-x86_64/sysroot)",
    );
    const ndk_api = b.option(
        []const u8,
        "ndk-api",
        "Android API level (default: 27)",
    ) orelse "30";

    const mod = b.addModule("ncore2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "ncore2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ncore2", .module = mod },
            },
        }),
    });

    const lib = b.addLibrary(.{
        .name = "ncore2",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/jni.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    if (optimize != .Debug) {
        exe.root_module.strip = true;
        exe.pie = true;
        exe.lto = .full;
        lib.root_module.strip = true;
        lib.lto = .full;
    }

    if (target.result.abi == .android) {
        const sysroot = ndk_sysroot orelse {
            std.debug.print("error: -Dndk-sysroot=<path> is required for Android targets\n", .{});
            return error.MissingNdkSysroot;
        };

        const arch_name = @tagName(target.result.cpu.arch);
        const triple = b.fmt("{s}-linux-android", .{arch_name});
        const include = b.pathJoin(&.{ sysroot, "usr/include" });
        const arch_include = b.pathJoin(&.{ include, triple });
        const libpath = b.pathJoin(&.{ sysroot, "usr/lib", triple, ndk_api });

        const libc_content = b.fmt(
            \\include_dir={s}
            \\sys_include_dir={s}
            \\crt_dir={s}
            \\msvc_lib_dir=
            \\kernel32_lib_dir=
            \\gcc_dir=
        , .{ include, include, libpath });
        const libc_path = b.addWriteFiles().add("libc.txt", libc_content);

        for (&[_]*std.Build.Step.Compile{lib}) |artifact| {
            artifact.root_module.addIncludePath(.{ .cwd_relative = include });
            artifact.root_module.addIncludePath(.{ .cwd_relative = arch_include });
            artifact.root_module.addLibraryPath(.{ .cwd_relative = libpath });
            artifact.root_module.linkSystemLibrary("log", .{});
            artifact.root_module.linkSystemLibrary("c", .{});
            artifact.setLibCFile(libc_path);
        }
        mod.addIncludePath(.{ .cwd_relative = include });
        mod.addLibraryPath(.{ .cwd_relative = libpath });
    }

    b.installArtifact(exe);
    b.installArtifact(lib);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
