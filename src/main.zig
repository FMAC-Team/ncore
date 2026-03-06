const std = @import("std");
const ncore = @import("ncore");

const log = @import("log.zig");

const exe_name = "ncore";

fn unpack_boot(allocator: std.mem.Allocator, imgfile: []const u8) !void {
    const file = try std.fs.cwd().openFile(imgfile, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    const unpacked = try ncore.boot.unpack_boot_image(buffer);

    if (unpacked.kernel.len > 0) {
        try log.info_f("Kernel size: {d} bytes\n", .{unpacked.kernel.len});
        const out_file = try std.fs.cwd().createFile("kernel.raw", .{});
        defer out_file.close();
        try out_file.writeAll(unpacked.kernel);
        std.debug.print("Saved kernel.raw\n", .{});
    }
    if (unpacked.ramdisk.len > 0) {
        try log.info_f("Ramdisk size: {d} bytes\n", .{unpacked.ramdisk.len});
        const out_file = try std.fs.cwd().createFile("ramdisk", .{});
        defer out_file.close();
        try out_file.writeAll(unpacked.ramdisk);
        std.debug.print("Saved ramdisk\n", .{});
    }
    if (unpacked.second.len > 0) {
        try log.info_f("second size: {d} bytes\n", .{unpacked.second.len});
        const out_file = try std.fs.cwd().createFile("second", .{});
        defer out_file.close();
        try out_file.writeAll(unpacked.second);
        std.debug.print("Saved second\n", .{});
    }
    if (unpacked.recovery_dtbo.len > 0) {
        try log.info_f("recovery_dtbo size: {d} bytes\n", .{unpacked.recovery_dtbo.len});
        const out_file = try std.fs.cwd().createFile("recovery_dtbo", .{});
        defer out_file.close();
        try out_file.writeAll(unpacked.recovery_dtbo);
        std.debug.print("Saved recovery_dtbo\n", .{});
    }
    if (unpacked.dtb.len > 0) {
        try log.info_f("dtb size: {d} bytes\n", .{unpacked.dtb.len});
        const out_file = try std.fs.cwd().createFile("dtb", .{});
        defer out_file.close();
        try out_file.writeAll(unpacked.dtb);
        std.debug.print("Saved dtb\n", .{});
    }
}

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
    log.pr_bcyan("  -u, --unpack \n", .{});
    try log.info("          Unpack boot image.\n");
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
    unpackboot,
    unknown,

    const meql = std.mem.eql;
    pub fn getcmd(s: []const u8) parg {
        if (meql(u8, s, "--base32") or meql(u8, s, "-b")) return .b32;
        if (meql(u8, s, "--code") or meql(u8, s, "-c")) return .totp;
        if (meql(u8, s, "--help") or meql(u8, s, "-h")) return .help;
        if (meql(u8, s, "--unpack") or meql(u8, s, "-u")) return .unpackboot;
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
        .unpackboot => {
            if (args.len < 3) {
                log.pr_bred("error", .{});
                try log.info(": less argument\n");
                try log.info_f("try {s} -u [file]\n", .{args[0]});
                return;
            }
            try unpack_boot(allocator, args[2]);
        },
        .unknown => {
            log.pr_bred("error", .{});
            try log.info_f(": no such command: `{s}`\n\n", .{args[1]});
        },
    }
}
