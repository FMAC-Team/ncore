const std = @import("std");

const c = @cImport({
    @cInclude("jni.h");
});

pub fn check_all_files_permission(env: *c.JNIEnv) bool {
    const cls = env.*.*.FindClass.?(
        env,
        "android/os/Environment",
    );
    if (cls == null) return false;

    const method = env.*.*.GetStaticMethodID.?(
        env,
        cls,
        "isExternalStorageManager",
        "()Z",
    );
    if (method == null) return false;

    const result = env.*.*.CallStaticBooleanMethod.?(
        env,
        cls,
        method,
    );

    return result == c.JNI_TRUE;
}
