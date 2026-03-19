const std = @import("std");
const config = @import("config");

const log = @import("log.zig");
const totp = @import("totp.zig");
const ctl = @import("ctl.zig");
const path = @import("path.zig");

const c = @cImport({
    @cInclude("jni.h");
});

const tag = "ncore";

var fd: i32 = -1;

// JNI_OnLoad put on init.zig

export fn Java_me_nekosu_aqnya_ncore_helloLog(
    env: *c.JNIEnv,
    thiz: c.jobject,
) callconv(.c) void {
    _ = env;
    _ = thiz;

    const storage = path.getPath();

    log.info("Hello, this is a log from Zig!");
    log.logToAndroid(.DEBUG, "Debug info: Program is running...");
    log.logToAndroid2(.INFO, "path: {s}", .{storage});
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

    if (fd > -1) {
        return 0;
    }

    const op: ctl.opcode = switch (value) {
        1 => ctl.opcode.authenticate,
        2 => ctl.opcode.getRoot,
        else => return -1,
    };

    const ev = ctl.Event.init() catch |err| {
        log.info_f("init eventfd err: {}", .{err});
        return -1;
    };
    defer ev.deinit();

    const result: isize = ctl.ctl(op, .{
        .fd = @intFromPtr(&fd),
        .eventfd = @intCast(ev.fd),
    }) catch |err| {
        log.logToAndroid2(.ERROR, "ctl error: {any}", .{@errorName(err)});
        return -1;
    };
    log.logToAndroid2(.ERROR, "ctl fd: {d}", .{fd});
    log.logToAndroid2(.ERROR, "ctl result: {d}", .{result});
    //   if (fd > 0) {
    //       return 0;
    //   } else {
    //    return @truncate(result);
    // }
    const count = ev.waitWithTimeout(50) catch |err| {
        log.info_f("failed to wait eventfd: {}", .{err});
        return -1;
    };
    log.info_f("finished: {d}\n", .{count});
    if (count < 0) {
        return -1;
    }
    return 0;
}
