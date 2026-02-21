const std = @import("std");

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

pub extern "log" fn __android_log_print(prio: i32, tag: [*:0]const u8, fmt: [*:0]const u8, ...) i32;

pub fn logToAndroid(prio: LogPriority, tag: [:0]const u8, message: [:0]const u8) void {
    _ = __android_log_print(@intFromEnum(prio), tag, "%s", message.ptr);
}

pub fn logToAndroid2(
    prio: LogPriority,
    tag: [:0]const u8,
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buf: [1024]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, fmt, args) catch "log message too long";

    _ = __android_log_print(@intFromEnum(prio), tag.ptr, "%s", message.ptr);
}
