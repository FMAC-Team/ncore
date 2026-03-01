const std = @import("std");
const config = @import("config");
const linux = std.os.linux;

const path = @import("path.zig");
const log = @import("log.zig");

const c = @cImport({
    @cInclude("jni.h");
    @cInclude("sys/prctl.h");
});

pub var app_path: []u8 = &[_]u8{};
var jvm: *c.JavaVM = undefined;

fn ok(rc: usize) bool {
    return @as(isize, @bitCast(rc)) >= 0;
}

fn flags_set() void {
    if (!ok(linux.syscall2(.prctl, c.PR_SET_DUMPABLE, 0))) log.info("Dumpable failed"); // prctl(PR_SET_DUMPABLE, 0);
}

export fn JNI_OnLoad(vm: *c.JavaVM, reserved: ?*anyopaque) c.jint {
    _ = reserved;
    jvm = vm;

    flags_set();

    var env: *c.JNIEnv = undefined;
    if (vm.*.*.GetEnv.?(vm, @ptrCast(&env), c.JNI_VERSION_1_6) == c.JNI_OK) {
        if (path.fetchPathFromSystem(env)) |p| {
            app_path = p;
        } else |_| {
            // TODO
        }
    }

    return c.JNI_VERSION_1_6;
}
