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
    try log.info("\n");
}

const parg = enum {
    b32,
    help,
    unknown,

    pub fn getcmd(s: []const u8) parg {
        if (std.mem.eql(u8, s, "--base32") or std.mem.eql(u8, s, "-b")) return .b32;
        if (std.mem.eql(u8, s, "--help") or std.mem.eql(u8, s, "-h")) return .help;
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
        .b32 => unreachable, // TODO
        .help => try prUsage(),
        .unknown => {
            log.pr_bred("error", .{});
            try log.info_f(": no such command: `{s}`\n\n", .{args[1]});
        },
    }
}
