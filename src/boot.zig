const std = @import("std");
const head = @import("boot_head.zig");

pub const ImageError = error{
    BufferTooSmall,
    BadMagic,
    UnexpectedVersion,
    Unknown,
    OutOfMemory,
};

pub const BootImage = union(enum) {
    V0: *const head.boot_img_hdr_v0,
    V1: *const head.boot_img_hdr_v1,
    V2: *const head.boot_img_hdr_v2,
    V3: *const head.boot_img_hdr_v3,
    V4: *const head.boot_img_hdr_v4,
};

pub const UnpackedBoot = struct {
    kernel: []const u8 = &[_]u8{},
    ramdisk: []const u8 = &[_]u8{},
    second: []const u8 = &[_]u8{},
    recovery_dtbo: []const u8 = &[_]u8{},
    dtb: []const u8 = &[_]u8{},
    signature: []const u8 = &[_]u8{},
};

fn align_size(size: usize, page_size: usize) usize {
    if (page_size == 0) return size;
    return (size + page_size - 1) & ~(page_size - 1);
}

fn get_section(buffer: []const u8, offset: *usize, size: u64, page_size: usize) ImageError![]const u8 {
    if (size == 0) return &[_]u8{};

    const start = offset.*;
    const end = start + @as(usize, size);

    if (end > buffer.len) return ImageError.BufferTooSmall;

    const section = buffer[start..end];
    offset.* += align_size(@as(usize, size), page_size);

    return section;
}

fn write_section(dest: []u8, data: []const u8, page_size: usize) usize {
    if (data.len == 0) return 0;
    @memcpy(dest[0..data.len], data);
    return align_size(data.len, page_size);
}

fn check_size(buffer: []const u8, comptime T: type) ImageError!*const T {
    if (buffer.len < @sizeOf(T)) return ImageError.BufferTooSmall;
    return @ptrCast(@alignCast(buffer.ptr));
}

pub fn parse_boot_image(buffer: []const u8) ImageError!BootImage {
    if (buffer.len < @sizeOf(head.boot_img_hdr_v3)) return ImageError.BufferTooSmall;

    const hdr_v3: *const head.boot_img_hdr_v3 = @ptrCast(@alignCast(buffer.ptr));
    const magic_size = head.BOOT_MAGIC_SIZE;

    if (!std.mem.eql(u8, hdr_v3.magic[0..magic_size], head.BOOT_MAGIC[0..magic_size])) {
        return ImageError.BadMagic;
    }

    return switch (hdr_v3.header_version) {
        0 => BootImage{ .V0 = try check_size(buffer, head.boot_img_hdr_v0) },
        1 => BootImage{ .V1 = try check_size(buffer, head.boot_img_hdr_v1) },
        2 => BootImage{ .V2 = try check_size(buffer, head.boot_img_hdr_v2) },
        3 => BootImage{ .V3 = try check_size(buffer, head.boot_img_hdr_v3) },
        4 => BootImage{ .V4 = try check_size(buffer, head.boot_img_hdr_v4) },
        else => ImageError.UnexpectedVersion,
    };
}

pub fn unpack_boot_image(buffer: []const u8) ImageError!UnpackedBoot {
    const boot_img = try parse_boot_image(buffer);
    var unpacked = UnpackedBoot{};
    var offset: usize = 0;

    switch (boot_img) {
        .V0, .V1, .V2 => {
            const v0 = switch (boot_img) {
                .V0 => |h| h,
                .V1 => |h| &h.base,
                .V2 => |h| &h.base.base,
                else => unreachable,
            };

            const page_size = @as(usize, v0.page_size);
            offset = page_size;
            unpacked.kernel = try get_section(buffer, &offset, v0.kernel_size, page_size);
            unpacked.ramdisk = try get_section(buffer, &offset, v0.ramdisk_size, page_size);
            unpacked.second = try get_section(buffer, &offset, v0.second_size, page_size);

            if (boot_img == .V1) {
                const h1 = boot_img.V1;
                unpacked.recovery_dtbo = try get_section(buffer, &offset, h1.recovery_dtbo_size, page_size);
            } else if (boot_img == .V2) {
                const h2 = boot_img.V2;
                unpacked.recovery_dtbo = try get_section(buffer, &offset, h2.base.recovery_dtbo_size, page_size);
                unpacked.dtb = try get_section(buffer, &offset, h2.dtb_size, page_size);
            }
        },

        .V3, .V4 => {
            const v3 = switch (boot_img) {
                .V3 => |h| h,
                .V4 => |h| &h.base,
                else => unreachable,
            };

            const page_size: usize = 4096;
            offset = align_size(@as(usize, v3.header_size), page_size);

            unpacked.kernel = try get_section(buffer, &offset, v3.kernel_size, page_size);
            unpacked.ramdisk = try get_section(buffer, &offset, v3.ramdisk_size, page_size);

            if (boot_img == .V4) {
                unpacked.signature = try get_section(buffer, &offset, boot_img.V4.signature_size, page_size);
            }
        },
    }

    return unpacked;
}

pub fn repack_boot_image(fd: i32, original_buffer: []const u8, unpacked: UnpackedBoot) !void {
    const boot_img = try parse_boot_image(original_buffer);

    var total_size: usize = 0;
    var page_size: usize = 0;

    switch (boot_img) {
        .V0, .V1, .V2 => {
            const v0 = switch (boot_img) {
                .V0 => |h| h,
                .V1 => |h| &h.base,
                .V2 => |h| &h.base.base,
                else => unreachable,
            };
            page_size = @as(usize, v0.page_size);
            total_size += page_size;
            total_size += align_size(unpacked.kernel.len, page_size);
            total_size += align_size(unpacked.ramdisk.len, page_size);
            total_size += align_size(unpacked.second.len, page_size);

            if (boot_img == .V1 or boot_img == .V2) {
                total_size += align_size(unpacked.recovery_dtbo.len, page_size);
            }
            if (boot_img == .V2) {
                total_size += align_size(unpacked.dtb.len, page_size);
            }
        },
        .V3, .V4 => {
            page_size = 4096;
            const v3 = switch (boot_img) {
                .V3 => |h| h,
                .V4 => |h| &h.base,
                else => unreachable,
            };
            total_size += align_size(@as(usize, v3.header_size), page_size);
            total_size += align_size(unpacked.kernel.len, page_size);
            total_size += align_size(unpacked.ramdisk.len, page_size);

            if (boot_img == .V4) {
                total_size += align_size(unpacked.signature.len, page_size);
            }
        },
    }

    try std.posix.ftruncate(fd, total_size);

    const out_buffer = try std.posix.mmap(
        null,
        total_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED, .POPULATE = true },
        fd,
        0,
    );
    defer std.posix.munmap(out_buffer);

    var offset: usize = 0;

    switch (boot_img) {
        .V0, .V1, .V2 => {
            var hdr_len: usize = 0;
            switch (boot_img) {
                .V0 => hdr_len = @sizeOf(head.boot_img_hdr_v0),
                .V1 => hdr_len = @sizeOf(head.boot_img_hdr_v1),
                .V2 => hdr_len = @sizeOf(head.boot_img_hdr_v2),
                else => unreachable,
            }

            @memcpy(out_buffer[0..hdr_len], original_buffer[0..hdr_len]);

            const out_v0: *head.boot_img_hdr_v0 = @ptrCast(@alignCast(out_buffer.ptr));
            out_v0.kernel_size = @intCast(unpacked.kernel.len);
            out_v0.ramdisk_size = @intCast(unpacked.ramdisk.len);
            out_v0.second_size = @intCast(unpacked.second.len);

            if (boot_img == .V1 or boot_img == .V2) {
                const out_v1: *head.boot_img_hdr_v1 = @ptrCast(@alignCast(out_buffer.ptr));
                out_v1.recovery_dtbo_size = @intCast(unpacked.recovery_dtbo.len);
            }
            if (boot_img == .V2) {
                const out_v2: *head.boot_img_hdr_v2 = @ptrCast(@alignCast(out_buffer.ptr));
                out_v2.dtb_size = @intCast(unpacked.dtb.len);
            }

            offset = page_size;
            offset += write_section(out_buffer[offset..], unpacked.kernel, page_size);
            offset += write_section(out_buffer[offset..], unpacked.ramdisk, page_size);
            offset += write_section(out_buffer[offset..], unpacked.second, page_size);

            if (boot_img == .V1 or boot_img == .V2) {
                offset += write_section(out_buffer[offset..], unpacked.recovery_dtbo, page_size);
            }
            if (boot_img == .V2) {
                offset += write_section(out_buffer[offset..], unpacked.dtb, page_size);
            }
        },
        .V3, .V4 => {
            var hdr_len: usize = 0;
            switch (boot_img) {
                .V3 => hdr_len = @sizeOf(head.boot_img_hdr_v3),
                .V4 => hdr_len = @sizeOf(head.boot_img_hdr_v4),
                else => unreachable,
            }

            @memcpy(out_buffer[0..hdr_len], original_buffer[0..hdr_len]);

            const out_v3: *head.boot_img_hdr_v3 = @ptrCast(@alignCast(out_buffer.ptr));
            out_v3.kernel_size = @intCast(unpacked.kernel.len);
            out_v3.ramdisk_size = @intCast(unpacked.ramdisk.len);

            if (boot_img == .V4) {
                const out_v4: *head.boot_img_hdr_v4 = @ptrCast(@alignCast(out_buffer.ptr));
                out_v4.signature_size = @intCast(unpacked.signature.len);
            }

            const v3 = switch (boot_img) {
                .V3 => |h| h,
                .V4 => |h| &h.base,
                else => unreachable,
            };
            offset = align_size(@as(usize, v3.header_size), page_size);

            offset += write_section(out_buffer[offset..], unpacked.kernel, page_size);
            offset += write_section(out_buffer[offset..], unpacked.ramdisk, page_size);

            if (boot_img == .V4) {
                offset += write_section(out_buffer[offset..], unpacked.signature, page_size);
            }
        },
    }
}
