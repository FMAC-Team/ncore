const std = @import("std");
const config = @import("config");

pub const LogPriority = enum(i32) {
    UNKNOWN = 0,
    DEFAULT = 1,
    VERBOSE = 2,
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7,
    SILENT = 8,
};

const tag = "ncore";

pub extern "log" fn __android_log_print(prio: i32, tag: [*:0]const u8, fmt: [*:0]const u8, ...) i32;

pub fn logToAndroid(prio: LogPriority, message: [:0]const u8) void {
    _ = __android_log_print(@intFromEnum(prio), tag, "%s", message.ptr);
}

pub fn logToAndroid2(
    prio: LogPriority,
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buf: [1024]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, fmt, args) catch "log message too long";

    _ = __android_log_print(@intFromEnum(prio), tag, "%s", message.ptr);
}

fn grt() type {
    if (comptime config.is_lib) {
        return void;
    } else {
        return anyerror!void;
    }
}

fn log(prio: LogPriority, comptime fmt: []const u8, args: anytype) grt() {
    if (comptime config.is_lib) {
        logToAndroid2(prio, fmt, args);
    } else {
        std.debug.print(fmt, args);
    }
}

pub fn info(message: []const u8) grt() {
    if (comptime config.is_lib) {
        log(.INFO, "{s}", .{message});
    } else {
        return try log(.INFO, "{s}", .{message});
    }
}
