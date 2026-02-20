const std = @import("std");

pub const Base32Error = error{
    InvalidCharacter,
    InvalidLength,
    BufferTooSmall,
};

fn charToValue(c: u8) !u5 {
    return switch (c) {
        'A'...'Z' => @intCast(c - 'A'),
        'a'...'z' => @intCast(c - 'a'),
        '2'...'7' => @intCast(c - '2' + 26),
        else => error.InvalidCharacter,
    };
}

pub fn decode(dest: []u8, src: []const u8) ![]u8 {
    var len = src.len;
    while (len > 0 and src[len - 1] == '=') : (len -= 1) {}
    const clean_src = src[0..len];
    const expected_len = (clean_src.len * 5) / 8;
    if (dest.len < expected_len) return error.BufferTooSmall;

    var buffer: u40 = 0;
    var bits_left: u6 = 0;
    var out_idx: usize = 0;

    for (clean_src) |c| {
        const val = try charToValue(c);

        buffer = (buffer << 5) | val;
        bits_left += 5;

        if (bits_left >= 8) {
            bits_left -= 8;
            dest[out_idx] = @intCast((buffer >> bits_left) & 0xFF);
            out_idx += 1;
        }
    }
    return dest[0..out_idx];
}
