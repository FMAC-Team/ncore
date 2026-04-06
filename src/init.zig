const std = @import("std");
const config = @import("config");
const linux = std.os.linux;

const path = @import("jreflect.zig");
const jreflect = path;
const log = @import("log.zig");
const necd = @import("ecdsa.zig");
const perm = @import("permission.zig");
const devinfo = @import("info.zig");

const c = @cImport({
    @cInclude("jni.h");
    @cInclude("sys/prctl.h");
    @cInclude("sys/resource.h");
    @cInclude("sys/ptrace.h");
    @cInclude("linux/seccomp.h");
    @cInclude("linux/filter.h");
    @cInclude("unistd.h");
    @cInclude("sys/utsname.h");
});

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

fn allow(nr: u32) [2]c.struct_sock_filter {
    return .{
        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, nr, 0, 1),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
    };
}

fn set_seccomp() !void {
    var filter = [_]c.struct_sock_filter{
        stmt(c.BPF_LD | c.BPF_W | c.BPF_ABS, @offsetOf(c.struct_seccomp_data, "arch")),
        jump(c.BPF_JMP | c.BPF_JEQ | c.BPF_K, 0xC00000B7, 1, 0), // AUDIT_ARCH_AARCH64
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),
        stmt(c.BPF_LD | c.BPF_W | c.BPF_ABS, @offsetOf(c.struct_seccomp_data, "nr")),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 435, 0, 1),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),

        // [17] getcwd
    } ++ allow(17) ++ .{
        // [19] eventfd2
    } ++ allow(19) ++ .{
        // [20-22] epoll_create1, epoll_ctl, epoll_pwait
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 20, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 22, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [25] fcntl
    } ++ allow(25) ++ .{
        // [29] ioctl
    } ++ allow(29) ++ .{
        // [34-35] mkdirat, unlinkat
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 34, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 35, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [38] renameat
    } ++ allow(38) ++ .{
        // [43-44] statfs, fstatfs
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 43, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 44, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [46-48] ftruncate, fallocate, faccessat
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 46, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 48, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [53-54] fchmodat, fchownat
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 53, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 54, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [56-57] openat, close
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 56, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 57, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [59] pipe2
    } ++ allow(59) ++ .{
        // [61-87] getdents64..timerfd_gettime
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 61, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 87, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),

        // [90-91] capget, capset
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 90, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 91, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [93-103] exit..getitimer
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 93, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 103, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [113-115] clock_gettime, clock_getres, clock_nanosleep
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 113, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 115, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [119-124] sched_*
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 119, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 124, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [130-135] tkill..rt_sigprocmask
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 130, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 135, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [139] rt_sigreturn
    } ++ allow(139) ++ .{
        // [148] getresuid, [150] getresgid
    } ++ allow(148) ++ allow(150) ++ .{
        // [160] uname
    } ++ allow(160) ++ .{
        // [167] prctl
    } ++ allow(167) ++ .{
        // [169] gettimeofday
    } ++ allow(169) ++ .{
        // [172] getpid, [174-178] getuid..gettid
    } ++ allow(172) ++ .{
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 174, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 178, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [194-200] shmget..socket
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 194, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 200, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [201-212] listen..recvmsg
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 201, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 212, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [214-215] brk, munmap
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 214, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 215, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [220] clone, [222] mmap
    } ++ allow(220) ++ allow(222) ++ .{
        // [226-227] mprotect, msync
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 226, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 227, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [233] madvise
    } ++ allow(233) ++ .{
        // [242] accept4
    } ++ allow(242) ++ .{
        // [278-279] getrandom, memfd_create
        jump(c.BPF_JMP | c.BPF_JGE | c.BPF_K, 278, 1, 0),
        jump(c.BPF_JMP | c.BPF_JGT | c.BPF_K, 279, 1, 0),
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_ALLOW),
        // [435] clone3
    } ++ allow(435) ++ .{
        stmt(c.BPF_RET | c.BPF_K, c.SECCOMP_RET_KILL_PROCESS),
    };

    var prog = c.struct_sock_fprog{
        .len = filter.len,
        .filter = &filter,
    };

    if (linux.syscall5(.prctl, c.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0)
        return error.PrctlFailed;

    if (linux.syscall3(.seccomp, c.SECCOMP_SET_MODE_FILTER, c.SECCOMP_FILTER_FLAG_TSYNC, @intFromPtr(&prog)) < 0)
        return error.SeccompFailed;
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
    _ = vm;

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

    return c.JNI_VERSION_1_6;
}
