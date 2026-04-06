const std = @import("std");
const config = @import("config");

const init = @import("init.zig");

const jni = @cImport({
    @cInclude("jni.h");
});
const allocator = std.heap.page_allocator;

pub var app_context: jni.jobject = null;
var java_vm: *jni.JavaVM = undefined;

threadlocal var tls_env: ?*jni.JNIEnv = null;
threadlocal var tls_attached: bool = false;

pub fn saveJavaVM(vm: *jni.JavaVM) void {
    java_vm = vm;
}

pub fn getEnv() !*jni.JNIEnv {
    if (tls_env) |env| return env;

    var env: *jni.JNIEnv = undefined;
    const rc = java_vm.*.*.GetEnv.?(java_vm, @ptrCast(&env), jni.JNI_VERSION_1_6);
    switch (rc) {
        jni.JNI_OK => {
            tls_env = env;
            return env;
        },
        jni.JNI_EDETACHED => {
            var args = jni.JavaVMAttachArgs{
                .version = jni.JNI_VERSION_1_6,
                .name = "ncore-worker",
                .group = null,
            };
            const ar = java_vm.*.*.AttachCurrentThread.?(java_vm, @ptrCast(&env), &args);
            if (ar != jni.JNI_OK) return error.AttachFailed;
            tls_env = env;
            tls_attached = true;
            return env;
        },
        else => return error.GetEnvFailed,
    }
}

pub fn detachIfAttached() void {
    if (!tls_attached) return;
    _ = java_vm.*.*.DetachCurrentThread.?(java_vm);
    tls_env = null;
    tls_attached = false;
}

pub fn savejrt(env: *jni.JNIEnv) !void {
    var vm: *jni.JavaVM = undefined;
    if (env.*.*.GetJavaVM.?(env, @ptrCast(&vm)) != 0) return error.GetVMFailed;
    saveJavaVM(vm);

    const j = env.*.*;
    const at_class = j.FindClass.?(env, "android/app/ActivityThread") orelse return error.ClassNotFound;
    const get_app_mid = j.GetStaticMethodID.?(env, at_class, "currentApplication", "()Landroid/app/Application;") orelse return error.MethodNotFound;
    const context = j.CallStaticObjectMethod.?(env, at_class, get_app_mid) orelse return error.ContextNotFound;
    if (app_context != null) {
        j.DeleteGlobalRef.?(env, app_context);
    }
    app_context = j.NewGlobalRef.?(env, context);
}

pub fn fetchPathFromSystem() ![]u8 {
    const env = try getEnv();
    const j = env.*.*;
    const context = app_context;
    const ctx_class = j.FindClass.?(env, "android/content/Context") orelse return error.ClassNotFound;
    defer j.DeleteLocalRef.?(env, ctx_class);
    const get_files_mid = j.GetMethodID.?(env, ctx_class, "getFilesDir", "()Ljava/io/File;") orelse return error.MethodNotFound;
    const file_obj = j.CallObjectMethod.?(env, context, get_files_mid) orelse return error.ContextNotFound;
    defer j.DeleteLocalRef.?(env, file_obj);

    const file_class = j.FindClass.?(env, "java/io/File") orelse return error.ClassNotFound;
    defer j.DeleteLocalRef.?(env, file_class);
    const get_path_mid = j.GetMethodID.?(env, file_class, "getAbsolutePath", "()Ljava/lang/String;") orelse return error.MethodNotFound;
    const j_path: jni.jstring = @ptrCast(j.CallObjectMethod.?(env, file_obj, get_path_mid) orelse return error.ContextNotFound);
    defer j.DeleteLocalRef.?(env, j_path);

    const chars = j.GetStringUTFChars.?(env, j_path, null) orelse return error.StringNull;
    defer j.ReleaseStringUTFChars.?(env, j_path, chars);

    return try allocator.dupe(u8, std.mem.span(chars));
}

pub fn load_key_from_keyutils(key_out: *[32]u8) !void {
    const env = try getEnv();
    const iface = env.*.*;
    const context = app_context;

    const cls = iface.FindClass.?(env, "me/nekosu/aqnya/KeyUtils") orelse return error.ClassNotFound;
    defer iface.DeleteLocalRef.?(env, cls);

    const instance_fid = iface.GetStaticFieldID.?(env, cls, "INSTANCE", "Lme/nekosu/aqnya/KeyUtils;") orelse return error.FieldNotFound;
    const instance = iface.GetStaticObjectField.?(env, cls, instance_fid) orelse return error.InstanceNull;
    defer iface.DeleteLocalRef.?(env, instance);

    const mid = iface.GetMethodID.?(env, cls, "loadKeyBytes", "(Landroid/content/Context;)[B") orelse return error.MethodNotFound;

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

    iface.GetByteArrayRegion.?(env, jba, 0, 32, @ptrCast(key_out));
    if (iface.ExceptionCheck.?(env) != 0) {
        iface.ExceptionClear.?(env);
        key_out.* = std.mem.zeroes([32]u8);
        return error.CopyFailed;
    }
}
