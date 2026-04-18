const std = @import("std");
const config = @import("config");

const log = @import("log.zig");
const totp = @import("totp.zig");
const ctl = @import("ctl.zig");
const path = @import("jreflect.zig");
const info = @import("info.zig");
const perm = @import("permission.zig");
const guard = @import("value_guard.zig");
const devinfo = info;
const jreflect = path;

const c = @cImport({
    @cInclude("jni.h");
    @cInclude("fcntl.h");
    @cInclude("android/log.h");
    @cInclude("time.h");
    @cInclude("sys/uio.h");
});

const tag = "ncore";
var jvm: *c.JavaVM = undefined;

var fd: i32 = -1;
var ctlfd: i32 = -1;

export fn JNI_OnLoad(vm: *c.JavaVM, reserved: ?*anyopaque) c.jint {
    guard.initGuardKey();
    _ = reserved;
    jvm = vm;

    _ = ctl.ctl(ctl.opcode.authenticate) catch |err| {
        log.logToAndroid2(.ERROR, "ctl error: {any}", .{@errorName(err)});
    };

    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) == c.JNI_OK) {
        jreflect.savejrt(env) catch |err| {
            log.info_f("failed to save jrt:{}", .{err});
            @panic("jrt was necessary");
        };
        if (path.fetchPathFromSystem()) |data_path| {
            init_log(data_path);
        } else |_| {
            @panic("failed to fetch data path!");
        }
    }

    return c.JNI_VERSION_1_6;
}

export fn Java_me_nekosu_aqnya_ncore_addSelinuxRule(
    env: *c.JNIEnv,
    thiz: c.jobject,
    src: c.jstring,
    tgt: c.jstring,
    cls: c.jstring,
    perm_str: c.jstring,
    effect: c.jint,
    invert: c.jboolean,
) callconv(.c) c.jint {
    _ = thiz;

    const jget = env.*.*.GetStringUTFChars.?;
    const jrel = env.*.*.ReleaseStringUTFChars.?;

    const src_ptr = if (src != null) jget(env, src, null) else null;
    const tgt_ptr = if (tgt != null) jget(env, tgt, null) else null;
    const cls_ptr = if (cls != null) jget(env, cls, null) else null;
    const perm_ptr = if (perm_str != null) jget(env, perm_str, null) else null;

    defer if (src_ptr != null) jrel(env, src, src_ptr);
    defer if (tgt_ptr != null) jrel(env, tgt, tgt_ptr);
    defer if (cls_ptr != null) jrel(env, cls, cls_ptr);
    defer if (perm_ptr != null) jrel(env, perm_str, perm_ptr);

    const src_sl = if (src_ptr != null) src_ptr[0..std.mem.len(src_ptr)] else null;
    const tgt_sl = if (tgt_ptr != null) tgt_ptr[0..std.mem.len(tgt_ptr)] else null;
    const cls_sl = if (cls_ptr != null) cls_ptr[0..std.mem.len(cls_ptr)] else null;
    const perm_sl = if (perm_ptr != null) perm_ptr[0..std.mem.len(perm_ptr)] else null;

    ctl.addSelinuxRule(ctlfd, src_sl, tgt_sl, cls_sl, perm_sl, effect, invert != 0) catch |err| {
        log.info_f("addSelinuxRule failed: {}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_setCap(
    env: *c.JNIEnv,
    thiz: c.jobject,
    uid: c.jint,
    caps: c.jlong,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;

    if (uid < 0) return -1;
    ctl.setCap(ctlfd, @intCast(uid), @bitCast(caps)) catch |err| {
        log.info_f("setCap failed:{}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_getCap(
    env: *c.JNIEnv,
    thiz: c.jobject,
    uid: c.jint,
) callconv(.c) c.jlong {
    _ = thiz;
    _ = env;

    if (uid < 0) return -1;
    const caps = ctl.getCap(ctlfd, @intCast(uid)) catch |err| {
        log.info_f("getCap failed:{}", .{err});
        return -1;
    };
    return @bitCast(caps);
}

export fn Java_me_nekosu_aqnya_ncore_delCap(
    env: *c.JNIEnv,
    thiz: c.jobject,
    uid: c.jint,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;

    if (uid < 0) return -1;
    ctl.delCap(ctlfd, @intCast(uid)) catch |err| {
        log.info_f("delCap failed:{}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_helloLog(
    env: *c.JNIEnv,
    thiz: c.jobject,
) callconv(.c) void {
    _ = env;
    _ = thiz;

    log.info("Hello, this is a log from Zig!");
    log.logToAndroid(.DEBUG, "Debug info: Program is running...");
    if (comptime config.is_lib) {
        log.logToAndroid(.INFO, "ncore build-as lib");
    }
}

export fn Java_me_nekosu_aqnya_ncore_ctl(
    env: *c.JNIEnv,
    thiz: c.jobject,
    value: c.jint,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;

    const op: ctl.opcode = switch (value) {
        1 => ctl.opcode.authenticate,
        2 => ctl.opcode.getRoot,
        3 => ctl.opcode.ioctl,
        else => return -1,
    };

    const result: isize = ctl.ctl(op) catch |err| {
        log.logToAndroid2(.ERROR, "ctl error: {any}", .{@errorName(err)});
        return -1;
    };
    if (value == 1) {
        ctl.scanDriverFd(&fd) catch |err| {
            log.info_f("fail to scan fd:{}", .{err});
        };
    }
    if (value == 3) {
        ctl.scanCtlFd(&ctlfd) catch |err| {
            log.info_f("fail to scan fd:{}", .{err});
        };
        log.info_f("ctlfd after scan: {d}", .{ctlfd});
    }

    log.logToAndroid2(.INFO, "ctl fd: {d}", .{fd});
    log.logToAndroid2(.INFO, "ctl result: {d}", .{result});
    if (fd < 0) {
        return -1;
    }
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_adduid(
    env: *c.JNIEnv,
    thiz: c.jobject,
    value: c.jint,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;
    ctl.addUid(ctlfd, value) catch |err| {
        log.info_f("adduid failed:{}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_deluid(
    env: *c.JNIEnv,
    thiz: c.jobject,
    value: c.jint,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;
    ctl.delUid(ctlfd, value) catch |err| {
        log.info_f("deluid failed:{}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_hasuid(
    env: *c.JNIEnv,
    thiz: c.jobject,
    value: c.jint,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;
    if (ctl.hasUid(ctlfd, value)) |has| {
        return if (has) 1 else 0;
    } else |_| {
        return -1;
    }
}

export fn Java_me_nekosu_aqnya_ncore_addRule(
    env: *c.JNIEnv,
    thiz: c.jobject,
    path_str: c.jstring,
    status_bits: c.jlong,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;
    _ = path_str;
    _ = status_bits;
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_delRule(
    env: *c.JNIEnv,
    thiz: c.jobject,
    path_str: c.jstring,
) callconv(.c) c.jint {
    _ = thiz;
    _ = env;
    _ = path_str;
    return 0;
}

fn custom_logger(log_message: [*c]const c.__android_log_message) callconv(.c) void {
    if (logfd == -1) return;

    devinfo.loadDeviceInfo(logfd);
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

    _ = c.writev(logfd, &iovecs, iovecs.len);

    c.__android_log_logd_logger(log_message);
}

var logfd: i32 = undefined;

fn init_log(data_path: []const u8) void {
    var path_buf: [512]u8 = undefined;
    const log_path = std.fmt.bufPrintZ(&path_buf, "{s}/debug.log", .{data_path}) catch {
        return;
    };

    const lfd = c.open(log_path.ptr, c.O_CREAT | c.O_WRONLY | c.O_TRUNC | c.O_CLOEXEC, @as(c_int, 0o666));
    if (lfd >= 0) {
        logfd = lfd;
        c.__android_log_set_logger(custom_logger);
    }
}
