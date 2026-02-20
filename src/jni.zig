const std = @import("std");

pub const log = @import("log.zig");
const totp = @import("totp.zig");

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
