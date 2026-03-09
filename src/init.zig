const std = @import("std");
const config = @import("config");
const linux = std.os.linux;

const path = @import("path.zig");
const log = @import("log.zig");
const perm = @import("permission.zig");
const devinfo = @import("deviceInfo.zig");

const c = @cImport({
    @cInclude("jni.h");
    @cInclude("sys/prctl.h");
    @cInclude("sys/resource.h");
    @cInclude("sys/ptrace.h");
    @cInclude("linux/seccomp.h");
    @cInclude("linux/filter.h");
    @cInclude("android/log.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/uio.h");
    @cInclude("time.h");
    @cInclude("sys/utsname.h");
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

        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, @intCast(@intFromEnum(linux.SYS.execve)), 0, 1),
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

    if (linux.syscall3(.seccomp, c.SECCOMP_SET_MODE_FILTER, c.SECCOMP_FILTER_FLAG_TSYNC, @intFromPtr(&prog)) < 0) {
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

var log_file_fd: i32 = -1;

fn custom_logger(log_message: [*c]const c.__android_log_message) callconv(.c) void {
    if (log_file_fd == -1) return;

    devinfo.loadDeviceInfo(log_file_fd);
    const msg = log_message.*;

    var timer: c.time_t = undefined;
    var now: c.struct_tm = undefined;
    _ = c.time(&timer);
    _ = c.localtime_r(&timer, &now);

    var time_buf: [32]u8 = undefined; // "HH:MM:SS"
    const time = std.fmt.bufPrint(
        &time_buf,
        "[{d:0>4}/{d:0>2}/{d:0>2} {:0>2}:{:0>2}:{:0>2}]",
        .{ @as(u32, @intCast(now.tm_year + 1900)), @as(u32, @intCast(now.tm_mon + 1)), @as(u32, @intCast(now.tm_mday)), @as(u8, @intCast(now.tm_hour)), @as(u8, @intCast(now.tm_min)), @as(u8, @intCast(now.tm_sec)) },
    ) catch |err| {
        log.logToAndroid2(.ERROR, "format time failed: {}", .{err});
        return;
    };

    var iovecs = [_]c.struct_iovec{
        .{ .iov_base = @constCast(time.ptr), .iov_len = time.len },
        .{ .iov_base = @constCast(" ".ptr), .iov_len = 1 },
        .{ .iov_base = @constCast(msg.tag), .iov_len = @intCast(std.mem.len(msg.tag)) },
        .{ .iov_base = @constCast(": ".ptr), .iov_len = 2 },
        .{ .iov_base = @constCast(msg.message), .iov_len = @intCast(std.mem.len(msg.message)) },
        .{ .iov_base = @constCast("\n".ptr), .iov_len = 1 },
    };

    _ = c.writev(log_file_fd, &iovecs, iovecs.len);

    c.__android_log_logd_logger(log_message);
}

fn init_log() void {
    var path_buf: [512]u8 = undefined;
    const log_path = std.fmt.bufPrintZ(&path_buf, "{s}/debug.log", .{app_path}) catch {
        return;
    };

    const fd = c.open(log_path.ptr, c.O_CREAT | c.O_WRONLY | c.O_TRUNC | c.O_CLOEXEC, @as(c_int, 0o666));
    if (fd >= 0) {
        log_file_fd = fd;
        c.__android_log_set_logger(custom_logger);
    }
}

export fn JNI_OnLoad(vm: *c.JavaVM, reserved: ?*anyopaque) c.jint {
    _ = reserved;
    jvm = vm;

    flags_set();
    if (comptime config.debug) {
        log.info("set flags\n");
    }
    set_seccomp() catch |err| {
        log.info_f("seccomp failed with error: {s}", .{@errorName(err)});
        _ = linux.syscall1(.exit_group, 1);
    };
    if (comptime config.debug) {
        log.info("set seccomp\n");
    }

    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) == c.JNI_OK) {
        if (path.fetchPathFromSystem(env)) |p| {
            app_path = p;
            init_log();
        } else |_| {
            // TODO
        }

        if (!perm.check_all_files_permission(env)) {
            log.info("MANAGE_EXTERNAL_STORAGE not granted");
        }
    }

    return c.JNI_VERSION_1_6;
}
