const std = @import("std");

var memory_guard_key: [32]u8 = undefined;
var is_key_initialized: std.atomic.Value(bool) = .{ .raw = false };
var canary_value: u64 = undefined;

pub fn initGuardKey() void {
    std.crypto.random.bytes(&memory_guard_key);
    std.crypto.random.bytes(std.mem.asBytes(&canary_value));
    is_key_initialized.store(true, .release);
}

pub fn Guarded(comptime T: type) type {
    comptime {
        if (@typeInfo(T) == .Struct) {
            if (@typeInfo(T).Struct.layout == .auto) {
                @compileError("Guarded(T): use extern or packed struct to guarantee no padding");
            }
        }
    }

    return struct {
        const CanaryType = u64;

        head_canary: CanaryType,
        value: T,
        mac: [32]u8,
        tail_canary: CanaryType,

        const Self = @This();

        pub fn init(v: T) Self {
            if (!is_key_initialized.load(.acquire)) {
                @panic("Guarded: initGuardKey() not called!");
            }

            var self = Self{
                .head_canary = canary_value,
                .value = v,
                .mac = undefined,
                .tail_canary = canary_value,
            };
            self.rehash();
            return self;
        }

        fn computeMac(v: *const T) [32]u8 {
            var mac_out: [32]u8 = undefined;
            var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(&memory_guard_key);
            hmac.update(std.mem.asBytes(v));
            hmac.final(&mac_out);
            return mac_out;
        }

        fn rehash(self: *Self) void {
            self.mac = computeMac(&self.value);
        }

        pub fn verify(self: *const Self) void {
            const cv = canary_value;
            if (self.head_canary != cv or self.tail_canary != cv) {
                @panic("Guarded: canary mismatch (buffer overflow)!");
            }
            const expected = computeMac(&self.value);
            if (!std.crypto.utils.timingSafeEql([32]u8, expected, self.mac)) {
                @panic("Guarded: MAC mismatch (value forged)!");
            }
        }

        pub fn get(self: *const Self) T {
            self.verify();
            return self.value;
        }

        pub fn set(self: *Self, v: T) void {
            self.verify();
            self.value = v;
            self.rehash();
        }

        pub fn mutate(self: *Self, ctx: anytype, f: fn (@TypeOf(ctx), *T) void) void {
            self.verify();
            f(ctx, &self.value);
            self.rehash();
        }
    };
}
