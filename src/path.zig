const std = @import("std");
const config = @import("config");

const init = @import("init.zig");

const jni = @cImport({
    @cInclude("jni.h");
});
const allocator: std.mem.Allocator = undefined;

pub fn fetchPathFromSystem(env: *jni.JNIEnv) ![]u8 {
    const j = env.*.*;

    const at_class = j.FindClass.?(env, "android/app/ActivityThread");
    const get_app_mid = j.GetStaticMethodID.?(env, at_class, "currentApplication", "()Landroid/app/Application;");
    const context = j.CallStaticObjectMethod.?(env, at_class, get_app_mid);

    const ctx_class = j.FindClass.?(env, "android/content/Context");
    const get_files_mid = j.GetMethodID.?(env, ctx_class, "getFilesDir", "()Ljava/io/File;");
    const file_obj = j.CallObjectMethod.?(env, context, get_files_mid);

    const file_class = j.FindClass.?(env, "java/io/File");
    const get_path_mid = j.GetMethodID.?(env, file_class, "getAbsolutePath", "()Ljava/lang/String;");
    const j_path = @as(jni.jstring, @ptrCast(j.CallObjectMethod.?(env, file_obj, get_path_mid)));

    const chars = j.GetStringUTFChars.?(env, j_path, null);
    defer j.ReleaseStringUTFChars.?(env, j_path, chars);

    return try allocator.dupe(u8, std.mem.span(chars));
}

pub fn getPath() []const u8 {
    return init.app_path;
}
