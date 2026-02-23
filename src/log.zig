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

const color = struct {
    pub const reset = "\x1b[0m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const bold = "\x1b[1m";
    pub const bold_green = "\x1b[1;32m";
    pub const bold_red = "\x1b[1;31m";
    pub const bold_yellow = "\x1b[1;33m";
    pub const bold_cyan = "\x1b[1;36m";
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

pub fn log(prio: LogPriority, comptime fmt: []const u8, args: anytype) grt() {
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

pub fn info_f(comptime message: []const u8, args: anytype) grt() {
    if (comptime config.is_lib) {
        log(.INFO, message, args);
    } else {
        return try log(.INFO, message, args);
    }
}

fn pr(comptime color_code: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(color_code ++ fmt ++ color.reset ++ "\n", args);
}

pub fn pr_green(comptime fmt: []const u8, args: anytype) void {
    pr(color.green, fmt, args);
}

pub fn pr_bgreen(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(color.bold_green ++ fmt ++ color.reset, args);
}

pub fn pr_bred(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(color.bold_red ++ fmt ++ color.reset, args);
}

pub fn pr_bcyan(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(color.bold_cyan ++ fmt ++ color.reset, args);
}

pub fn pr_red(comptime fmt: []const u8, args: anytype) void {
    pr(color.red, fmt, args);
}

pub fn pr_yellow(comptime fmt: []const u8, args: anytype) void {
    pr(color.yellow, fmt, args);
}

pub fn pr_blue(comptime fmt: []const u8, args: anytype) void {
    pr(color.blue, fmt, args);
}

pub fn pr_cyan(comptime fmt: []const u8, args: anytype) void {
    pr(color.cyan, fmt, args);
}

pub fn pr_bold(comptime fmt: []const u8, args: anytype) void {
    pr(color.bold, fmt, args);
}
