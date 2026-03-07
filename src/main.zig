const std = @import("std");
const ncore = @import("ncore");

const log = @import("log.zig");

const exe_name = "ncore";

fn save(name: []const u8, data: []const u8) !void {
    if (data.len == 0) return;

    log.pr_bcyan("[info] ", .{});
    try log.info_f("{s} size: {d} bytes\n", .{ name, data.len });

    const file = try std.fs.cwd().createFile(name, .{});
    defer file.close();

    try file.writeAll(data);

    std.debug.print("Saved {s}\n", .{name});
}

pub fn unpack_boot(imgfile: []const u8) !void {
    const file = try std.fs.cwd().openFile(imgfile, .{});
    defer file.close();

    const size: usize = @intCast(try file.getEndPos());

    const mapped = try std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        file.handle,
        0,
    );
    defer std.posix.munmap(mapped);

    const unpacked = try ncore.boot.unpack_boot_image(mapped);

    const Section = struct {
        name: []const u8,
        data: []const u8,
    };

    const sections = [_]Section{
        .{ .name = "kernel", .data = unpacked.kernel },
        .{ .name = "ramdisk", .data = unpacked.ramdisk },
        .{ .name = "second", .data = unpacked.second },
        .{ .name = "recovery_dtbo", .data = unpacked.recovery_dtbo },
        .{ .name = "dtb", .data = unpacked.dtb },
    };

    inline for (sections) |s| {
        try save(s.name, s.data);
    }
}

fn replaceboot(oboot: []const u8, section: []const u8, op: isize) !void {
    const section_file = try std.fs.cwd().openFile(section, .{});
    const boot_file = try std.fs.cwd().openFile(oboot, .{});
    const fd = try std.posix.open("new_boot.img", .{
        .ACCMODE = .RDWR,
        .CREAT = true,
    }, 0o644);
    defer boot_file.close();
    defer section_file.close();
    defer std.posix.close(fd);

    const boot_size: usize = @intCast(try boot_file.getEndPos());
    const section_size: usize = @intCast(try section_file.getEndPos());

    const boot_mapped = try std.posix.mmap(
        null,
        boot_size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        boot_file.handle,
        0,
    );
    const section_mapped = try std.posix.mmap(
        null,
        section_size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        section_file.handle,
        0,
    );
    defer std.posix.munmap(boot_mapped);
    defer std.posix.munmap(section_mapped);

    var unpacked = try ncore.boot.unpack_boot_image(boot_mapped);

    switch (op) {
        1 => unpacked.kernel = section_mapped,
        2 => unpacked.ramdisk = section_mapped,
        else => {
            log.pr_bred("error: ", .{});
            try log.info("unknown option\n");
            try log.info("try kernel ramdisk etc.\n");
            try log.info_f("such as ./{s} -r kernel boot.img kernel.lz4\n", .{exe_name});
            return;
        },
    }
    try ncore.boot.repack_boot_image(fd, boot_mapped, unpacked);
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
    log.pr_bcyan("  -r, --replace \n", .{});
    try log.info("          Replace boot image.\n");
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
    replaceboot,
    unknown,

    const meql = std.mem.eql;
    pub fn getcmd(s: []const u8) parg {
        if (meql(u8, s, "--base32") or meql(u8, s, "-b")) return .b32;
        if (meql(u8, s, "--code") or meql(u8, s, "-c")) return .totp;
        if (meql(u8, s, "--help") or meql(u8, s, "-h")) return .help;
        if (meql(u8, s, "--unpack") or meql(u8, s, "-u")) return .unpackboot;
        if (meql(u8, s, "--replace") or meql(u8, s, "-r")) return .replaceboot;
        return .unknown;
    }
};

fn replace_option(op: []const u8) isize {
    if (std.mem.eql(u8, op, "kernel")) {
        return 1;
    }
    if (std.mem.eql(u8, op, "ramdisk")) {
        return 2;
    }
    return 0;
}

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
            try unpack_boot(args[2]);
        },
        .replaceboot => {
            if (args.len < 5) {
                log.pr_bred("error", .{});
                try log.info(": less argument\n");
                try log.info_f("try {s} -r [option] boot.img [new file]\n", .{args[0]});
                return;
            }
            const op = replace_option(args[2]);
            try replaceboot(args[3], args[4], op);
        },
        .unknown => {
            log.pr_bred("error", .{});
            try log.info_f(": no such command: `{s}`\n\n", .{args[1]});
        },
    }
}
