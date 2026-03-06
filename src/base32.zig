const std = @import("std");

pub const Base32Error = error{
    InvalidCharacter,
    InvalidLength,
    BufferTooSmall,
    OutOfMemory,
};

inline fn charToValue(c: u8) !u5 {
    return switch (c) {
        'A'...'Z' => @intCast(c - 'A'),
        'a'...'z' => @intCast(c - 'a'),
        '2'...'7' => @intCast(c - '2' + 26),
        else => error.InvalidCharacter,
    };
}

pub fn decode(comptime src: []const u8) [countDecodedLen(src)]u8 {
    @setEvalBranchQuota(5000);

    const effective_src = comptime blk: {
        var len = src.len;
        while (len > 0 and src[len - 1] == '=') : (len -= 1) {}
        break :blk src[0..len];
    };

    const dest_len = (effective_src.len * 5) / 8;
    var dest: [dest_len]u8 = undefined;

    var buffer: u40 = 0;
    var bits_left: u6 = 0;
    var out_idx: usize = 0;

    inline for (effective_src) |c| {
        const val = charToValue(c) catch @compileError("Base32 contains invalid characters");

        buffer = (buffer << 5) | val;
        bits_left += 5;

        if (bits_left >= 8) {
            bits_left -= 8;
            dest[out_idx] = @intCast((buffer >> bits_left) & 0xFF);
            out_idx += 1;
        }
    }
    return dest;
}

fn countDecodedLen(comptime src: []const u8) usize {
    var len = src.len;
    while (len > 0 and src[len - 1] == '=') : (len -= 1) {}
    return (len * 5) / 8;
}

fn encodedLen(input_len: usize) usize {
    return (input_len * 8 + 4) / 5;
}

pub fn encode(
    allocator: std.mem.Allocator,
    input: []const u8,
) Base32Error![]u8 {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    const out_len = encodedLen(input.len);
    var out = try allocator.alloc(u8, out_len);

    var accumulator: u32 = 0;
    var bits: u8 = 0;
    var count: usize = 0;

    for (input) |byte| {
        accumulator = (accumulator << 8) | @as(u32, byte);
        bits += 8;

        while (bits >= 5) {
            bits -= 5;
            const shift: u5 = @intCast(bits);
            const index = @as(u5, @intCast((accumulator >> shift) & 0x1F));

            out[count] = alphabet[index];
            count += 1;
        }
    }

    if (bits > 0) {
        const shift: u5 = @intCast(5 - bits);
        const index: u5 = @intCast((accumulator << shift) & 0x1F);
        out[count] = alphabet[index];
        count += 1;
    }

    return out[0..count];
}

test "base32 decode no padding" {
    const testcode = decode("JBSWY3DPEBLW64TMMQQQ");
    try std.testing.expectEqualStrings("Hello World!", &testcode);
}

test "base32 encode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const b32code = try encode(allocator, "test");
    defer allocator.free(b32code);
    const code = "ORSXG5A";
    try std.testing.expectEqualStrings(code, b32code);
}
