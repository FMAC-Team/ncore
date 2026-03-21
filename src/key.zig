const std = @import("std");
const config = @import("config");
const base32 = @import("base32.zig");
const path = @import("path.zig");

const c = @cImport({
    @cInclude("jni.h");
});

pub const totp = base32.decode("P2U6KVKZKSFKXGXO7XN6S6X62X6M6NE7");

fn getKey(env: *c.JNIEnv) ?[]u8 {
    comptime {
        if (!config.is_lib) {
            @compileError("getKey is only available in lib mode");
        }
    }
    const cls = c.FindClass(env.*, "me/nekosu/aqnya/KeyUtils") orelse return null;
    const mid = c.GetStaticMethodID(env.*, cls, "loadKey", "(Landroid/content/Context;)[B") orelse return null;

    const result = c.CallStaticObjectMethod(env.*, cls, mid, path.app_context);
    if (result == null) return null;

    const arr: c.jbyteArray = @ptrCast(result);
    const len = c.GetArrayLength(env.*, arr);
    if (len <= 0) return null;

    const elements = c.GetByteArrayElements(env.*, arr, null) orelse return null;
    const pem = @as([*]const u8, @ptrCast(elements))[0..@intCast(len)];

    const buf = std.heap.c_allocator.dupe(u8, pem) catch {
        c.ReleaseByteArrayElements(env.*, arr, elements, c.JNI_ABORT);
        return null;
    };
    c.ReleaseByteArrayElements(env.*, arr, elements, c.JNI_ABORT);

    return buf;
}
