const std = @import("std");
const config = @import("config");

const totp = @import("totp.zig");
const log = @import("log.zig");
const ncrypto = @import("ecdsa.zig");
const linux = std.os.linux;
const posix = std.posix;
const fs = std.fs;

pub const opcode = enum(u32) {
    authenticate = 1,
    getRoot = 2,
    ioctl = 3,
    unknown,
};

pub const FmacRule = extern struct {
    path: [1024]u8,
    status_bits: u64,
};

pub const FmacUidCap = extern struct {
    uid: u32,
    caps: u64,
};

const MAGIC: u32 = 'F';

fn _IO(nr: u32) u32 {
    return (MAGIC << 8) | nr;
}
fn _IOW(nr: u32, comptime T: type) u32 {
    return 0x40000000 | (@as(u32, @sizeOf(T)) << 16) | (MAGIC << 8) | nr;
}
fn _IOR(nr: u32, comptime T: type) u32 {
    return 0x80000000 | (@as(u32, @sizeOf(T)) << 16) | (MAGIC << 8) | nr;
}
fn _IOWR(nr: u32, comptime T: type) u32 {
    return 0xC0000000 | (@as(u32, @sizeOf(T)) << 16) | (MAGIC << 8) | nr;
}

pub const IOC_GET_SHM = _IO(0);
pub const IOC_BIND_EVT = _IOW(1, u32);
pub const IOC_CHK_WRITE = _IOR(2, u32);
pub const IOC_ADD_UID = _IOW(3, u32);
pub const IOC_DEL_UID = _IOW(4, u32);
pub const IOC_HAS_UID = _IOWR(5, u32);
pub const IOC_SET_CAP = _IOW(6, FmacUidCap);
pub const IOC_GET_CAP = _IOWR(7, FmacUidCap);
pub const IOC_DEL_CAP = _IOW(8, FmacUidCap);

fn prctl1(op: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("prctl op: {d}\n", .{rop});
        } else {
            try log.info_f("prctl op: {d}\n", .{rop});
        }
    }
    return @bitCast(linux.syscall1(.prctl, rop));
}

fn prctl2(op: u32, arg1: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("prctl op: {d} arg1: {d}\n", .{ rop, arg1 });
        } else {
            try log.info_f("prctl op: {d} arg1: {d}\n", .{ rop, arg1 });
        }
    }
    return @bitCast(linux.syscall2(.prctl, rop, arg1));
}

fn prctl3(op: u32, arg1: u32, arg2: usize) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("prctl op: {d} arg1: {d} arg2: {d}\n", .{ rop, arg1, arg2 });
        } else {
            try log.info_f("prctl op: {d} arg1: {d} arg2: {d}\n", .{ rop, arg1, arg2 });
        }
    }
    return @bitCast(linux.syscall3(.prctl, rop, arg1, arg2));
}

fn prctl4(op: u32, arg1: u32, arg2: usize, arg3: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("prctl op: {d} a1: {d} a2: 0x{x} a3: {d}\n", .{ rop, arg1, arg2, arg3 });
        } else {
            try log.info_f("prctl op: {d} a1: {d} a2: 0x{x} a3: {d}\n", .{ rop, arg1, arg2, arg3 });
        }
    }
    return @bitCast(linux.syscall4(.prctl, rop, arg1, arg2, arg3));
}

fn ioctl(fd: i32, cmd: u32, arg: usize) !i32 {
    const rc: isize = @bitCast(linux.syscall3(
        .ioctl,
        @as(usize, @bitCast(@as(isize, fd))),
        cmd,
        arg,
    ));
    if (rc < 0) {
        log.info_f("ioctl errno={d}", .{-rc});
        const err: posix.E = @enumFromInt(-rc);
        return posix.unexpectedErrno(err);
    }
    return @intCast(rc);
}

pub fn addUid(fd: i32, uid: i32) !void {
    if (uid < 0) return error.InvalidUid;
    var val: u32 = @intCast(uid);
    _ = try ioctl(fd, IOC_ADD_UID, @intFromPtr(&val));
}

pub fn delUid(fd: i32, uid: i32) !void {
    if (uid < 0) return error.InvalidUid;
    var val: u32 = @intCast(uid);
    _ = try ioctl(fd, IOC_DEL_UID, @intFromPtr(&val));
}

pub fn hasUid(fd: i32, uid: i32) !bool {
    if (uid < 0) return error.InvalidUid;
    var val: u32 = @intCast(uid);
    _ = try ioctl(fd, IOC_HAS_UID, @intFromPtr(&val));
    return val != 0;
}

pub fn addRule(fd: i32, path: []const u8, status_bits: u64) !void {
    var rule = std.mem.zeroes(FmacRule);
    const copy_len = @min(path.len, rule.path.len - 1);
    @memcpy(rule.path[0..copy_len], path[0..copy_len]);
    rule.status_bits = status_bits;
    _ = try ioctl(fd, IOC_ADD_RULE, @intFromPtr(&rule));
}

pub fn delRule(fd: i32, path: []const u8) !void {
    var rule = std.mem.zeroes(FmacRule);
    const copy_len = @min(path.len, rule.path.len - 1);
    @memcpy(rule.path[0..copy_len], path[0..copy_len]);
    _ = try ioctl(fd, IOC_DEL_RULE, @intFromPtr(&rule));
}

pub fn setCap(fd: i32, uid: u32, caps: u64) !void {
    var uc = FmacUidCap{ .uid = uid, .caps = caps };
    _ = try ioctl(fd, IOC_SET_CAP, @intFromPtr(&uc));
}

pub fn getCap(fd: i32, uid: u32) !u64 {
    var uc = FmacUidCap{ .uid = uid, .caps = 0 };
    _ = try ioctl(fd, IOC_GET_CAP, @intFromPtr(&uc));
    return uc.caps;
}

pub fn delCap(fd: i32, uid: u32) !void {
    var uc = FmacUidCap{ .uid = uid, .caps = 0 };
    _ = try ioctl(fd, IOC_DEL_CAP, @intFromPtr(&uc));
}

pub fn ctl(code: opcode) !isize {
    switch (code) {
        .authenticate => {
            var sign_buf: [72]u8 = undefined;
            const key = try totp.generateTotp();
            const key_bytes = std.mem.asBytes(&key);
            _ = ncrypto.sign(key_bytes, &sign_buf) catch |err| {
                if (comptime config.is_lib) {
                    log.info_f("failed to sign key:{}", .{err});
                } else {
                    try log.info_f("failed to sign key:{}", .{err});
                }
            };
            return prctl3(@intFromEnum(opcode.authenticate), key, @intFromPtr(&sign_buf));
        },
        .getRoot => return prctl1(@intFromEnum(opcode.getRoot)),
        .ioctl => return prctl1(@intFromEnum(opcode.ioctl)),
        .unknown => return -1,
    }
}

pub fn scanDriverFd(fd: *i32) !void {
    try scanFdByLink(fd, "[fmac_shm]");
}

pub fn scanCtlFd(fd: *i32) !void {
    try scanFdByLink(fd, "[fmac_ctl]");
}

fn scanFdByLink(fd: *i32, target_link: []const u8) !void {
    var dir = try fs.openDirAbsolute("/proc/self/fd", .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const fd_num = std.fmt.parseInt(i32, entry.name, 10) catch continue;
        var link_buf: [256]u8 = undefined;
        const target = dir.readLink(entry.name, &link_buf) catch continue;
        if (std.mem.indexOf(u8, target, target_link) != null) {
            fd.* = fd_num;
            return;
        }
    }
}

pub const Event = struct {
    fd: i32,

    pub fn init() !Event {
        return .{ .fd = try posix.eventfd(0, linux.EFD.CLOEXEC) };
    }

    pub fn deinit(self: Event) void {
        posix.close(self.fd);
    }

    pub fn wait(self: Event) !u64 {
        var poll_fds = [_]posix.pollfd{.{
            .fd = self.fd,
            .events = linux.POLL.IN,
            .revents = 0,
        }};

        while (true) {
            const ready = try posix.poll(&poll_fds, -1);
            if (ready > 0 and (poll_fds[0].revents & linux.POLL.IN) != 0) {
                var buf: [8]u8 = undefined;
                const n = try posix.read(self.fd, &buf);
                if (n == 8) return std.mem.readInt(u64, &buf, .little);
            }
        }
    }

    pub fn waitWithTimeout(self: Event, timeout_ms: i32) !isize {
        var pfd = [_]posix.pollfd{.{
            .fd = self.fd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const rc = posix.poll(&pfd, timeout_ms) catch |err| {
            if (comptime config.is_lib) {
                log.info_f("poll error: {any}", .{@errorName(err)});
            } else {
                try log.info_f("poll error: {any}", .{@errorName(err)});
            }
            return -1;
        };

        if (rc <= 0) return -1;

        var val: u64 = 0;
        const n = try posix.read(self.fd, std.mem.asBytes(&val));
        if (n != 8) return error.ReadError;
        return @bitCast(val);
    }
};
