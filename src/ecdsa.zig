const std = @import("std");
const config = @import("config");
const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;

const log = @import("log.zig");
const jreflect = @import("jreflect.zig");

var no_key: bool = false;

pub fn sign(
    message: []const u8,
    out_der: *[72]u8,
) !usize {
    if (!no_key) {
        var key: [32]u8 = undefined;
        jreflect.load_key_from_keyutils(&key) catch |err| {
            if (comptime config.is_lib) {
                log.info_f("{}", .{err});
            } else {
                try log.info_f("{}", .{err});
            }
            no_key = true;
        };
        defer key = std.mem.zeroes([32]u8);
        const secret_key = try Ecdsa.SecretKey.fromBytes(key);
        const kp = try Ecdsa.KeyPair.fromSecretKey(secret_key);
        const sig = try kp.sign(message, null);
        return rs_to_der(&sig.toBytes(), out_der);
    }
    return 0;
}

fn rs_to_der(rs: *const [64]u8, out: *[72]u8) !usize {
    const r = rs[0..32];
    const s = rs[32..64];
    const rpad: u8 = if (r[0] & 0x80 != 0) 1 else 0;
    const spad: u8 = if (s[0] & 0x80 != 0) 1 else 0;
    const rlen: u8 = 32 + rpad;
    const slen: u8 = 32 + spad;
    const seq_len: u8 = 2 + rlen + 2 + slen;
    const total: usize = 2 + seq_len;
    if (total > 72) return error.Overflow;

    var off: usize = 0;
    out[off] = 0x30;
    off += 1;
    out[off] = seq_len;
    off += 1;
    out[off] = 0x02;
    off += 1;
    out[off] = rlen;
    off += 1;
    if (rpad != 0) {
        out[off] = 0x00;
        off += 1;
    }
    @memcpy(out[off .. off + 32], r);
    off += 32;
    out[off] = 0x02;
    off += 1;
    out[off] = slen;
    off += 1;
    if (spad != 0) {
        out[off] = 0x00;
        off += 1;
    }
    @memcpy(out[off .. off + 32], s);
    off += 32;
    return off;
}
