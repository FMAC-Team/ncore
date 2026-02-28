const std = @import("std");
const config = @import("config");
const base32 = @import("base32.zig");

pub const key = struct {
    pub const secret_data = base32.decode("P2U6KVKZKSFKXGXO7XN6S6X62X6M6NE7");
};
