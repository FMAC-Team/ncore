const std = @import("std");
const ncore = @import("ncore");

const log = @import("log.zig");

const exe_name = "ncore";

fn prUsage() !void {
    try log.info("nekosu userspace tool utils\n\n");
    log.pr_bgreen("Usage: ", .{});
    log.pr_bcyan("{s} ", .{exe_name});
    log.pr_cyan("[OPTIONS] [COMMAND]\n\n", .{});
    log.pr_bgreen("Options: \n", .{});
    log.pr_bcyan("  -b, --base32 \n", .{});
    try log.info("          Generate a TOTP key using base32 encoding.\n");
    log.pr_bcyan("  -c, --code \n", .{});
    try log.info("          Gen totp code by build-in key.\n");
    log.pr_bcyan("  -h, --help \n", .{});
    try log.info("          Print help.\n");
    try log.info("\n");
}

fn getb32(
    allocator: std.mem.Allocator,
) !void {
    const code = try ncore.totp.genKey(allocator);
    defer allocator.free(code);
    try log.info_f("{s}\n", .{code});
}

const parg = enum {
    b32,
    totp,
    help,
    unknown,

    const meql = std.mem.eql;
    pub fn getcmd(s: []const u8) parg {
        if (meql(u8, s, "--base32") or meql(u8, s, "-b")) return .b32;
        if (meql(u8, s, "--code") or meql(u8, s, "-c")) return .totp;
        if (meql(u8, s, "--help") or meql(u8, s, "-h")) return .help;
        return .unknown;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try prUsage();
        return;
    }

    const cmd = parg.getcmd(args[1]);
    switch (cmd) {
        .b32 => try getb32(allocator),
        .totp => {
            const code = try ncore.totp.generateTotp();
            try log.info_f("Totp code: {d}\n", .{code});
        },
        .help => try prUsage(),
        .unknown => {
            log.pr_bred("error", .{});
            try log.info_f(": no such command: `{s}`\n\n", .{args[1]});
        },
    }
}
