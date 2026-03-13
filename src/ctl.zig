const std = @import("std");
const config = @import("config");

const totp = @import("totp.zig");
const log = @import("log.zig");
const syscall = std.os.linux.syscall4;
const linux = std.os.linux;
const posix = std.posix;

pub const opcode = enum(u32) {
    authenticate = 1,
    getRoot = 2,
};

fn prctl(op: u32, arg1: u32, arg2: usize, arg3: u32) !isize {
    const rop = op + 200;
    if (comptime config.debug) {
        log.info_f("op: {d} a1: {d} a2: 0x{x} a3: {d}", .{ rop, arg1, arg2, arg3 });
    }
    const rc = syscall(.prctl, rop, arg1, arg2, arg3);
    return @bitCast(rc);
}

pub fn ctl(code: opcode, fd: usize, eventfd: u32) !isize {
    const totp_key = try totp.generateTotp();

    switch (code) {
        opcode.authenticate => {
            const ret = try prctl(@intFromEnum(opcode.authenticate), totp_key, fd, eventfd);
            return ret;
        },
        opcode.getRoot => {
            const ret = try prctl(@intFromEnum(opcode.getRoot), totp_key, fd, eventfd);
            return ret;
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
};
