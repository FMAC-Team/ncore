const std = @import("std");

pub const log = @import("log.zig");

const c = @cImport({
    @cInclude("jni.h");
});

export fn Java_com_example_ncore_NativeLib_helloLog(
    env: *c.JNIEnv,
    thiz: c.jobject,
) callconv(.c) void {
    _ = env;
    _ = thiz;

    const tag = "ZigAndroid";
    const msg = "你好，这是来自 Zig 的日志！";

    log.logToAndroid(.INFO, tag, msg);
    log.logToAndroid(.DEBUG, tag, "调试信息：程序正在运行...");
}
