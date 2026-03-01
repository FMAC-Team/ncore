const std = @import("std");
const config = @import("config");
const linux = std.os.linux;

const path = @import("path.zig");
const log = @import("log.zig");

const c = @cImport({
    @cInclude("jni.h");
    @cInclude("sys/prctl.h");
    @cInclude("sys/resource.h");
    @cInclude("sys/ptrace.h");
    @cInclude("linux/seccomp.h");
    @cInclude("linux/filter.h");
});

pub var app_path: []u8 = &[_]u8{};
var jvm: *c.JavaVM = undefined;

fn ok(rc: usize) bool {
    return @as(isize, @bitCast(rc)) >= 0;
}

fn stmt(code: u16, k: u32) c.struct_sock_filter {
    return .{
        .code = code,
        .jt = 0,
        .jf = 0,
        .k = k,
    };
}

fn jump(code: u16, k: u32, jt: u8, jf: u8) c.struct_sock_filter {
    return .{
        .code = code,
        .jt = jt,
        .jf = jf,
        .k = k,
    };
}

fn set_seccomp() !void {
    var filter = [_]c.struct_sock_filter{
        stmt(c.BPF_LD | c.BPF_W | c.BPF_ABS, @offsetOf(c.struct_seccomp_data, "arch")),
        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, 0xC00000B7, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),

        stmt(c.BPF_LD | c.BPF_W | c.BPF_ABS, @offsetOf(c.struct_seccomp_data, "nr")),

        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, @intCast(@intFromEnum(linux.SYS.ptrace)), 0, 1),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),

        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, @intCast(@intFromEnum(linux.SYS.process_vm_readv)), 0, 1),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),

        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, @intCast(@intFromEnum(linux.SYS.process_vm_writev)), 0, 1),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),

        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
    };

    var prog = c.struct_sock_fprog{
        .len = filter.len,
        .filter = &filter,
    };

    if (linux.syscall5(.prctl, c.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        return error.PrctlFailed;
    }

    if (linux.syscall3(.prctl, c.PR_SET_SECCOMP, c.SECCOMP_MODE_FILTER, @intFromPtr(&prog)) < 0) {
        return error.SeccompFailed;
    }
}

fn flags_set() void {
    const lim = c.struct_rlimit{
        .rlim_cur = 0,
        .rlim_max = 0,
    };
    if (!ok(linux.syscall2(.prctl, c.PR_SET_DUMPABLE, 0))) log.info("Dumpable failed"); // prctl(PR_SET_DUMPABLE, 0);
    if (!ok(linux.syscall2(.setrlimit, c.RLIMIT_CORE, @intFromPtr(&lim)))) log.info("set rlimit failed"); // setrlimit(RLIMIT_CORE, 0);
}

export fn JNI_OnLoad(vm: *c.JavaVM, reserved: ?*anyopaque) c.jint {
    _ = reserved;
    jvm = vm;

    flags_set();
    if (comptime config.debug) {
        log.info("set flags\n");
    }
    set_seccomp() catch |err| {
        log.info("seccomp failed with error: {s}", .{@errorName(err)});
    };
    if (comptime config.debug) {
        log.info("set seccomp\n");
    }

    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) == c.JNI_OK) {
        if (path.fetchPathFromSystem(env)) |p| {
            app_path = p;
        } else |_| {
            // TODO
        }
    }

    return c.JNI_VERSION_1_6;
}
