const std = @import("std");
const totp = @import("totp.zig");
const log = @import("log.zig");
const syscall = std.os.linux.syscall3;

pub const opcode = enum(u32) {
    authenticate = 1,
    getRoot = 2,
};

pub const NksuReply = packed struct {
    fd: i32,
    version: u32,
    flags: u32,
};

fn prctl(op: u32, arg1: u32, arg2: usize) !isize {
    const rop = op + 200;
    log.info_f("op:{d} a1:{d} a2:{d}", .{ rop, arg1, arg2 });
    const rc = syscall(.prctl, rop, arg1, arg2);
    return @bitCast(rc);
}

pub fn ctl(code: opcode, key: []const u8, reply: usize) !isize {
    const totp_key = try totp.generateTotp(key);

    switch (code) {
        opcode.authenticate => {
            const ret = try prctl(@intFromEnum(opcode.authenticate), totp_key, reply);
            return ret;
        },
        opcode.getRoot => {
            const ret = try prctl(@intFromEnum(opcode.getRoot), totp_key, reply);
            return ret;
        },
    }
}
