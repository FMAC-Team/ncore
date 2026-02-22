const std = @import("std");
const ncore = @import("ncore");

const log = @import("log.zig");

pub fn main() !void {
    const ret = try log.info("test");
    return ret;
}
