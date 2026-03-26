const std = @import("std");
const config = @import("config");

const log = @import("log.zig");
const ctl = @import("ctl.zig");

pub fn cmd(args: [][:0]u8) !void {
    if (args.len >= 2) {
        const a = args[1];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            try su_help();
            return;
        }
        if (std.mem.eql(u8, a, "-c")) {
            if (args.len < 3) {
                log.pr_bred("error: ", .{});
                try log.info("-c requires a command\n");
                return;
            }
            try runAs(args[2..]);
            return;
        }
    }

    const code = ctl.opcode.getRoot;
    try getRoot(code);
}

fn su_help() !void {
    try log.info("Usage: su [-h|--help]\n\n");
    log.pr_bgreen("Options:\n", .{});
    log.pr_bcyan("  -h, --help\n", .{});
    try log.info("          Print this help.\n");
    try log.info("\n");
    try log.info("When invoked as 'su', requests root via ncore kernel module.\n");
}

pub fn getRoot(op: ctl.opcode) !void {
    const result: isize = ctl.ctl(op) catch |err| {
        try log.info_f("ctl error: {any}", .{@errorName(err)});
        return;
    };
    if (comptime config.debug) {
        try log.info_f("result: {d}\n", .{result});
    }
    if (std.posix.getuid() != 0) {
        log.pr_bred("error: ", .{});
        try log.info("Permission denied.\n");
        return;
    } else {
        if (comptime config.debug) {
            try log.info("success\n");
        }
        const path: [*:0]const u8 = "/system/bin/sh";
        const argv = [_:null]?[*:0]const u8{path};

        const envp = [_:null]?[*:0]const u8{"PATH=/system/bin:/system/xbin"};

        const ret = std.os.linux.execve(path, &argv, &envp);

        const err = std.posix.errno(ret);

        if (err != .SUCCESS) {
            return std.posix.unexpectedErrno(err);
        }
        unreachable;
    }
}

fn runAs(run_args: [][:0]u8) !void {
    const result: isize = ctl.ctl(.getRoot) catch |err| {
        try log.info_f("ctl error: {any}", .{@errorName(err)});
        return;
    };
    if (comptime config.debug) {
        try log.info_f("result: {d}\n", .{result});
    }

    if (std.posix.getuid() != 0) {
        log.pr_bred("error: ", .{});
        try log.info("Permission denied.\n");
        return;
    }

    const sh: [*:0]const u8 = "/system/bin/sh";
    const argv = [_:null]?[*:0]const u8{ sh, "-c", run_args[0], null };
    const envp = [_:null]?[*:0]const u8{"PATH=/system/bin:/system/xbin:/sbin"};

    const ret = std.os.linux.execve(sh, &argv, &envp);
    const err = std.posix.errno(ret);
    if (err != .SUCCESS) {
        return std.posix.unexpectedErrno(err);
    }
    unreachable;
}
