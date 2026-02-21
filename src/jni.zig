const std = @import("std");

const log = @import("log.zig");
const totp = @import("totp.zig");
const ctl = @import("ctl.zig");

const c = @cImport({
    @cInclude("jni.h");
});

const tag = "ncore";

export fn Java_me_nekosu_aqnya_ncore_helloLog(
    env: *c.JNIEnv,
    thiz: c.jobject,
) callconv(.c) void {
    _ = env;
    _ = thiz;

    log.logToAndroid(.INFO, tag, "Hello, this is a log from Zig!");
    log.logToAndroid(.DEBUG, tag, "Debug info: Program is running...");
}

export fn Java_me_nekosu_aqnya_ncore_generateTotp(
    env: *c.JNIEnv,
    _: c.jclass,
    j_key: c.jstring,
) callconv(.c) c.jint {
    const key_ptr = env.*.*.GetStringUTFChars.?(env, j_key, null);
    if (key_ptr == null) return -1;
    defer env.*.*.ReleaseStringUTFChars.?(env, j_key, key_ptr);

    const key = std.mem.span(key_ptr);

    const code = totp.generateTotp(key) catch |err| {
        if (err == error.InvalidCharacter) {
            log.logToAndroid(.ERROR, "ncore", "Base32 contains invalid characters");
        } else {
            log.logToAndroid(.ERROR, "ncore", @errorName(err));
        }
        return -2;
    };

    return @intCast(code);
}

export fn Java_me_nekosu_aqnya_ncore_ctl(
    env: *c.JNIEnv,
    thiz: c.jobject,
    value: c.jint,
    j_key: c.jstring,
) callconv(.c) c.jint {
    const key_ptr = env.*.*.GetStringUTFChars.?(env, j_key, null);
    if (key_ptr == null) return -1;
    defer env.*.*.ReleaseStringUTFChars.?(env, j_key, key_ptr);
    const key = std.mem.span(key_ptr);
    _ = thiz;

    var reply: ctl.NksuReply = .{ .flags = 0, .version = 0, .fd = -1 };

    const op: ctl.opcode = switch (value) {
        1 => ctl.opcode.authenticate,
        2 => ctl.opcode.getRoot,
        else => return -1,
    };

    const result: isize = ctl.ctl(op, key, @intFromPtr(&reply)) catch |err| {
        log.logToAndroid2(.ERROR, "ncore", "ctl error: {any}", .{err});
        return -1;
    };
    log.logToAndroid2(.ERROR, "ncore", "ctl fd: {d}", .{reply.fd});
    log.logToAndroid2(.ERROR, "ncore", "ctl result: {d}", .{result});
    return @truncate(result);
}
