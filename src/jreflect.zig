const std = @import("std");
const config = @import("config");

const init = @import("init.zig");

const jni = @cImport({
    @cInclude("jni.h");
});
const allocator = std.heap.page_allocator;

pub var app_context: jni.jobject = null;
pub var JniEnv: *jni.JNIEnv = undefined;

pub fn savejrt(env: *jni.JNIEnv) !void {
    const j = env.*.*;
    const at_class = j.FindClass.?(env, "android/app/ActivityThread") orelse return error.ClassNotFound;
    const get_app_mid = j.GetStaticMethodID.?(env, at_class, "currentApplication", "()Landroid/app/Application;") orelse return error.MethodNotFound;
    const context = j.CallStaticObjectMethod.?(env, at_class, get_app_mid) orelse return error.ContextNotFound;
    if (app_context != null) {
        j.DeleteGlobalRef.?(env, app_context);
    }
    app_context = j.NewGlobalRef.?(env, context);
    JniEnv = env;
}

pub fn fetchPathFromSystem(env: *jni.JNIEnv) ![]u8 {
    const j = env.*.*;
    const context = app_context;
    const ctx_class = j.FindClass.?(env, "android/content/Context") orelse return error.ClassNotFound;
    const get_files_mid = j.GetMethodID.?(env, ctx_class, "getFilesDir", "()Ljava/io/File;") orelse return error.MethodNotFound;
    const file_obj = j.CallObjectMethod.?(env, context, get_files_mid) orelse return error.ContextNotFound;

    const file_class = j.FindClass.?(env, "java/io/File") orelse return error.ClassNotFound;
    const get_path_mid = j.GetMethodID.?(env, file_class, "getAbsolutePath", "()Ljava/lang/String;") orelse return error.MethodNotFound;
    const j_path = @as(jni.jstring, @ptrCast(j.CallObjectMethod.?(env, file_obj, get_path_mid))) orelse return error.ContextNotFound;

    const chars = j.GetStringUTFChars.?(env, j_path, null);
    defer j.ReleaseStringUTFChars.?(env, j_path, chars);

    return try allocator.dupe(u8, std.mem.span(chars));
}

pub fn load_key_from_keyutils(
    key_out: *[32]u8,
) !void {
    const context = app_context;
    const env = JniEnv;
    const iface = env.*.*;

    const cls = iface.FindClass.?(env, "me/nekosu/aqnya/KeyUtils") orelse return error.ClassNotFound;
    defer iface.DeleteLocalRef.?(env, cls);

    const instance_fid = iface.GetStaticFieldID.?(
        env,
        cls,
        "INSTANCE",
        "Lme/nekosu/aqnya/KeyUtils;",
    ) orelse return error.FieldNotFound;
    const instance = iface.GetStaticObjectField.?(env, cls, instance_fid) orelse return error.InstanceNull;
    defer iface.DeleteLocalRef.?(env, instance);

    const mid = iface.GetMethodID.?(
        env,
        cls,
        "loadKeyBytes",
        "(Landroid/content/Context;)[B",
    );
    if (mid == null) return error.MethodNotFound;

    const result = iface.CallObjectMethod.?(env, instance, mid, context);
    
    if (iface.ExceptionCheck.?(env) != 0) {
        iface.ExceptionClear.?(env);
        return error.JavaException;
    }
    if (result == null) return error.KeyNotFound;
    defer iface.DeleteLocalRef.?(env, result);

    const jba: jni.jbyteArray = @ptrCast(result);
    const len: usize = @intCast(iface.GetArrayLength.?(env, jba));
    if (len < 32) return error.KeyTooShort;

    iface.GetByteArrayRegion.?(
        env,
        jba,
        0,
        32,
        @ptrCast(key_out),
    );
    
    if (iface.ExceptionCheck.?(env) != 0) {
        iface.ExceptionClear.?(env);
        key_out.* = std.mem.zeroes([32]u8);
        return error.CopyFailed;
    }
}
