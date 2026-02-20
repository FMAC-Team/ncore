const std = @import("std");
const base32 = @import("base32.zig");
const crypto = std.crypto;
const Sha1 = crypto.hash.Sha1;
const HmacSha1 = crypto.auth.hmac.Hmac(Sha1);

pub fn generateTotp(key: []const u8) !u32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const secret_buf = try gpa.allocator().alloc(u8, key.len);
    defer gpa.allocator().free(secret_buf);

    const decoded = try base32.decode(secret_buf, key);

    const time_step: i64 = 30;
    const timestamp = std.time.timestamp();
    const counter = @as(u64, @intCast(@divFloor(timestamp, time_step)));

    var counter_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &counter_bytes, counter, .big);

    var hmac_result: [HmacSha1.mac_length]u8 = undefined;

    HmacSha1.create(&hmac_result, &counter_bytes, decoded);

    const offset = hmac_result[hmac_result.len - 1] & 0x0F;
    const sub_slice = hmac_result[offset .. offset + 4];

    var binary = std.mem.readInt(u32, sub_slice[0..4], .big);
    binary &= 0x7FFFFFFF;

    return binary % 1_000_000;
}
