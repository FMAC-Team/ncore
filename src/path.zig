const std = @import("std");
const config = @import("config");

const init = @import("init.zig");

const jni = @cImport({
    @cInclude("jni.h");
});
const allocator = std.heap.page_allocator;

pub var app_context: jni.jobject = null;

pub fn fetchPathFromSystem(env: *jni.JNIEnv) ![]u8 {
    const j = env.*.*;

    const at_class = j.FindClass.?(env, "android/app/ActivityThread") orelse return error.ClassNotFound;
    const get_app_mid = j.GetStaticMethodID.?(env, at_class, "currentApplication", "()Landroid/app/Application;") orelse return error.MethodNotFound;
    const context = j.CallStaticObjectMethod.?(env, at_class, get_app_mid) orelse return error.ContextNotFound;

    app_context = j.NewGlobalRef.?(env, context);

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

pub fn getPath() []const u8 {
    return init.app_path;
}
