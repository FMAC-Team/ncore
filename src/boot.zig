const std = @import("std");
const head = @import("boot_head.zig");

pub const ImageError = error{
    BufferTooSmall,
    BadMagic,
    UnexpectedVersion,
    Unknown,
};

pub const BootImage = union(enum) {
    V0: *const head.boot_img_hdr_v0,
    V1: *const head.boot_img_hdr_v1,
    V2: *const head.boot_img_hdr_v2,
    V3: *const head.boot_img_hdr_v3,
    V4: *const head.boot_img_hdr_v4,
};

pub const VendorImageHeader = union(enum) {
    V3: *const head.vendor_boot_img_hdr_v3,
    V4: *const head.vendor_boot_img_hdr_v4,
};

fn checkSize(buffer: []const u8, T: type) ImageError!*const T {
    if (buffer.len < @sizeOf(T))
        return ImageError.BufferTooSmall;

    return @ptrCast(buffer.ptr);
}

pub fn parseBootImage(buffer: []const u8) ImageError!BootImage {
    if (buffer.len < @sizeOf(head.boot_img_hdr_v3))
        return ImageError.BufferTooSmall;

    const hdr_v3: *const head.boot_img_hdr_v3 = @ptrCast(buffer.ptr);

    const magic_size = head.BOOT_MAGIC_SIZE;
    if (!std.mem.eql(
        u8,
        hdr_v3.magic[0..magic_size],
        head.BOOT_MAGIC[0..magic_size],
    )) {
        return ImageError.BadMagic;
    }

    switch (hdr_v3.header_version) {
        0 => {
            const ptr = try checkSize(buffer, head.boot_img_hdr_v0);
            return BootImage{ .V0 = ptr };
        },
        1 => {
            const ptr = try checkSize(buffer, head.boot_img_hdr_v1);
            return BootImage{ .V1 = ptr };
        },
        2 => {
            const ptr = try checkSize(buffer, head.boot_img_hdr_v2);
            return BootImage{ .V2 = ptr };
        },
        3 => {
            const ptr = try checkSize(buffer, head.boot_img_hdr_v3);
            return BootImage{ .V3 = ptr };
        },
        4 => {
            const ptr = try checkSize(buffer, head.boot_img_hdr_v4);
            return BootImage{ .V4 = ptr };
        },
        else => return ImageError.UnexpectedVersion,
    }
}

pub fn parseVendorImage(buffer: []const u8) ImageError!VendorImageHeader {
    if (buffer.len < @sizeOf(head.vendor_boot_img_hdr_v3))
        return ImageError.BufferTooSmall;

    const hdr: *const head.vendor_boot_img_hdr_v3 = @ptrCast(buffer.ptr);

    const magic_size = head.VENDOR_BOOT_MAGIC_SIZE;
    if (!std.mem.eql(
        u8,
        hdr.magic[0..magic_size],
        head.VENDOR_BOOT_MAGIC[0..magic_size],
    )) {
        return ImageError.BadMagic;
    }

    switch (hdr.header_version) {
        3 => {
            const ptr = try checkSize(buffer, head.vendor_boot_img_hdr_v3);
            return VendorImageHeader{ .V3 = ptr };
        },
        4 => {
            const ptr = try checkSize(buffer, head.vendor_boot_img_hdr_v4);
            return VendorImageHeader{ .V4 = ptr };
        },
        else => return ImageError.UnexpectedVersion,
    }
}
