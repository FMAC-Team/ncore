const std = @import("std");
const ncore = @import("ncore");
const config = ncore.config;

const log = ncore.log;

const exe_name = "ncore";

fn save(name: []const u8, data: []const u8) !void {
    if (data.len == 0) return;

    log.pr_bcyan("[info] ", .{});
    try log.info_f("{s} size: {d} bytes\n", .{ name, data.len });
    const fd = try std.posix.open(name, .{
        .ACCMODE = .RDWR,
        .CREAT = true,
    }, 0o644);
    try std.posix.ftruncate(fd, data.len);
    const out = try std.posix.mmap(
        null,
        data.len,
        std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );
    defer std.posix.munmap(out);
    defer std.posix.close(fd);

    if (data.len == 0) return;
    @memcpy(out[0..data.len], data);

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

    try std.posix.madvise(mapped.ptr, size, std.posix.MADV.SEQUENTIAL);

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
    log.pr_bcyan("  -k, --key \n", .{});
    try log.info("          Gen totp code by build-in key.\n");
    log.pr_bcyan("  -h, --help \n", .{});
    try log.info("          Print help.\n");
    log.pr_bcyan("  -u, --unpack \n", .{});
    try log.info("          Unpack boot image.\n");
    log.pr_bcyan("  -r, --replace \n", .{});
    try log.info("          Replace boot image.\n");
    log.pr_bcyan("  -c, --ctl \n", .{});
    try log.info("          Run debug ctl cmd.\n");
    log.pr_bcyan("  -l, --load \n", .{});
    try log.info("          Load kernel module.\n");
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
    ctl,
    load,
    unknown,

    const meql = std.mem.eql;
    pub fn getcmd(s: []const u8) parg {
        if (meql(u8, s, "--base32") or meql(u8, s, "-b")) return .b32;
        if (meql(u8, s, "--key") or meql(u8, s, "-k")) return .totp;
        if (meql(u8, s, "--help") or meql(u8, s, "-h")) return .help;
        if (meql(u8, s, "--unpack") or meql(u8, s, "-u")) return .unpackboot;
        if (meql(u8, s, "--replace") or meql(u8, s, "-r")) return .replaceboot;
        if (meql(u8, s, "--ctl") or meql(u8, s, "-c")) return .ctl;
        if (meql(u8, s, "--load") or meql(u8, s, "-l")) return .load;
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

fn parseOpcode(str: []const u8) !ncore.rctl.opcode {
    if (std.mem.eql(u8, str, "authenticate")) return .authenticate;
    if (std.mem.eql(u8, str, "getRoot")) return .getRoot;
    return error.InvalidOpcode;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var parts = std.mem.splitScalar(u8, args[0], '/');
    var last_part: []const u8 = undefined;
    while (parts.next()) |part| {
        last_part = part;
    }

    if (std.mem.eql(u8, last_part, "su")) {
        try ncore.su.cmd(args);
        return;
    }

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
        .ctl => {
            if (args.len < 3) {
                log.pr_bred("error", .{});
                try log.info(": less argument\n");
                try log.info_f("try {s} -c [code]\n", .{args[0]});
                return;
            }
            const op = try parseOpcode(args[2]);
            switch (op) {
                .authenticate => {
                    try authenticate(op);
                },
                .getRoot => {
                    try ncore.su.getRoot(op);
                },
                .unknown => {
                    try log.info("unknown code");
                },
            }
        },
        .load => {
            if (args.len < 3) {
                log.pr_bred("error", .{});
                try log.info(": less argument\n");
                try log.info_f("try {s} -l [path]\n", .{args[0]});
                return;
            } else {
                try ncore.load(allocator, args[2]);
            }
        },
        .unknown => {
            log.pr_bred("error", .{});
            try log.info_f(": no such command: `{s}`\n\n", .{args[1]});
        },
    }
}

fn authenticate(op: ncore.rctl.opcode) !void {
    const result: isize = ncore.ctl(op) catch |err| {
        try log.info_f("ctl error: {any}", .{@errorName(err)});
        return;
    };
    if (comptime config.debug) {
        try log.info_f("result: {d}", .{result});
    }
}
