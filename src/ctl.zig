const std = @import("std");
const config = @import("config");

const totp = @import("totp.zig");
const log = @import("log.zig");
const linux = std.os.linux;
const posix = std.posix;
const fs = std.fs;
const os = std.os;

pub const opcode = enum(u32) {
    authenticate = 1,
    getRoot = 2,
    unknown,
};

fn prctl4(op: u32, arg1: u32, arg2: usize, arg3: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("op: {d} a1: {d} a2: 0x{x} a3: {d}\n", .{ rop, arg1, arg2, arg3 });
        } else {
            try log.info_f("op: {d} a1: {d} a2: 0x{x} a3: {d}\n", .{ rop, arg1, arg2, arg3 });
        }
    }
    const rc = std.os.linux.syscall4(.prctl, rop, arg1, arg2, arg3);
    return @bitCast(rc);
}

fn prctl1(op: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("op: {d}\n", .{rop});
        } else {
            try log.info_f("op: {d}\n", .{rop});
        }
    }
    const rc = std.os.linux.syscall1(.prctl, rop);
    return @bitCast(rc);
}

fn prctl2(op: u32, arg1: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        if (comptime config.is_lib) {
            log.info_f("op: {d} arg1:{d}\n", .{ rop, arg1 });
        } else {
            try log.info_f("op: {d} arg1:{d}\n", .{ rop, arg1 });
        }
    }
    const rc = std.os.linux.syscall2(.prctl, rop, arg1);
    return @bitCast(rc);
}

pub fn ctl(code: opcode) !isize {
    const totp_key = try totp.generateTotp();

    switch (code) {
        opcode.authenticate => {
            const ret = try prctl2(@intFromEnum(opcode.authenticate), totp_key);
            return ret;
        },
        opcode.getRoot => {
            const ret = try prctl1(@intFromEnum(opcode.getRoot));
            return ret;
        },
        opcode.unknown => {
            return -1;
        },
    }
}

pub const Event = struct {
    fd: i32,

    pub fn init() !Event {
        const fd = try posix.eventfd(0, linux.EFD.CLOEXEC);
        return .{ .fd = fd };
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
            const ready_count = try posix.poll(&poll_fds, -1);

            if (ready_count > 0 and (poll_fds[0].revents & linux.POLL.IN) != 0) {
                var buffer: [8]u8 = undefined;
                const bytes_read = try posix.read(self.fd, &buffer);

                if (bytes_read == 8) {
                    return std.mem.readInt(u64, &buffer, .little);
                }
            }
        }
    }
    pub fn waitWithTimeout(self: Event, timeout_ms: i32) !isize {
        var pfd = [_]std.posix.pollfd{.{
            .fd = self.fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const rc = std.posix.poll(&pfd, timeout_ms) catch |err| {
            if (comptime config.is_lib) {
                log.info_f("failed to poll: {any}", .{@errorName(err)});
            } else {
                try log.info_f("failed to poll: {any}", .{@errorName(err)});
            }

            return -1;
        };
        if (rc <= 0) {
            return -1;
        }

        var val: u64 = 0;
        const bytes = try std.posix.read(self.fd, std.mem.asBytes(&val));
        if (bytes != 8) return error.ReadError;
        return @bitCast(val);
    }
};

pub fn scanDriverFd(fd: *i32) !void {
    var dir = try fs.openDirAbsolute("/proc/self/fd", .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        const fd_num = std.fmt.parseInt(i32, entry.name, 10) catch continue;

        var link_buf: [256]u8 = undefined;
        const target = dir.readLink(entry.name, &link_buf) catch continue;

        if (std.mem.indexOf(u8, target, "[fmac_shm]") != null) {
            fd.* = fd_num;
        }
    }
    return;
}
