const std = @import("std");
const config = @import("config");

const log = @import("log.zig");
const totp = @import("totp.zig");
const ctl = @import("ctl.zig");
const path = @import("jreflect.zig");
const info = @import("info.zig");

const c = @cImport({
    @cInclude("jni.h");
});

const tag = "ncore";

var fd: i32 = -1;
var ctlfd: i32 = -1;

// JNI_OnLoad put on init.zig

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

    if (ctlfd < 0) {
        ctl.scanCtlFd(&ctlfd) catch |err| {
            log.info_f("addRule: scan ctlfd failed:{s}", .{@errorName(err)});
            return -1;
        };
    }
    log.info_f("addRule: ctlfd={d}", .{ctlfd});

    const chars = env.*.*.GetStringUTFChars.?(env, path_str, null) orelse return -1;
    defer env.*.*.ReleaseStringUTFChars.?(env, path_str, chars);

    const slice = std.mem.span(chars);
    ctl.addRule(ctlfd, slice, @intCast(status_bits)) catch |err| {
        log.info_f("addRule failed:{}", .{err});
        return -1;
    };
    return 0;
}

export fn Java_me_nekosu_aqnya_ncore_delRule(
    env: *c.JNIEnv,
    thiz: c.jobject,
    path_str: c.jstring,
) callconv(.c) c.jint {
    _ = thiz;

    if (ctlfd < 0) {
        ctl.scanCtlFd(&ctlfd) catch |err| {
            log.info_f("delRule: scan ctlfd failed:{s}", .{@errorName(err)});
            return -1;
        };
    }
    log.info_f("delRule: ctlfd={d}", .{ctlfd});

    const chars = env.*.*.GetStringUTFChars.?(env, path_str, null) orelse return -1;
    defer env.*.*.ReleaseStringUTFChars.?(env, path_str, chars);

    const slice = std.mem.span(chars);
    ctl.delRule(ctlfd, slice) catch |err| {
        log.info_f("delRule failed:{}", .{err});
        return -1;
    };
    return 0;
}
