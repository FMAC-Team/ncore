const std = @import("std");

pub const BOOT_MAGIC = "ANDROID!";
pub const BOOT_MAGIC_SIZE = 8;
pub const BOOT_NAME_SIZE = 16;
pub const BOOT_ARGS_SIZE = 512;
pub const BOOT_EXTRA_ARGS_SIZE = 1024;

pub const VENDOR_BOOT_MAGIC = "VNDRBOOT";
pub const VENDOR_BOOT_MAGIC_SIZE = 8;
pub const VENDOR_BOOT_ARGS_SIZE = 2048;
pub const VENDOR_BOOT_NAME_SIZE = 16;

pub const VENDOR_RAMDISK_TYPE_NONE = 0;
pub const VENDOR_RAMDISK_TYPE_PLATFORM = 1;
pub const VENDOR_RAMDISK_TYPE_RECOVERY = 2;
pub const VENDOR_RAMDISK_TYPE_DLKM = 3;
pub const VENDOR_RAMDISK_NAME_SIZE = 32;
pub const VENDOR_RAMDISK_TABLE_ENTRY_BOARD_ID_SIZE = 16;

pub const boot_img_hdr_v0 = extern struct {
    magic: [BOOT_MAGIC_SIZE]u8,
    kernel_size: u32,
    kernel_addr: u32,
    ramdisk_size: u32,
    ramdisk_addr: u32,
    second_size: u32,
    second_addr: u32,
    tags_addr: u32,
    page_size: u32,
    header_version: u32,
    os_version: u32,
    name: [BOOT_NAME_SIZE]u8,
    cmdline: [BOOT_ARGS_SIZE]u8,
    id: [8]u32,
    extra_cmdline: [BOOT_EXTRA_ARGS_SIZE]u8,
};

pub const boot_img_hdr_v1 = extern struct {
    base: boot_img_hdr_v0,
    recovery_dtbo_size: u32,
    recovery_dtbo_offset: u64,
    header_size: u32,
};

pub const boot_img_hdr_v2 = extern struct {
    base: boot_img_hdr_v1,
    dtb_size: u32,
    dtb_addr: u64,
};

pub const boot_img_hdr_v3 = extern struct {
    magic: [BOOT_MAGIC_SIZE]u8,
    kernel_size: u32,
    ramdisk_size: u32,
    os_version: u32,
    header_size: u32,
    reserved: [4]u32,
    header_version: u32,
    cmdline: [BOOT_ARGS_SIZE + BOOT_EXTRA_ARGS_SIZE]u8,
};

pub const boot_img_hdr_v4 = extern struct {
    base: boot_img_hdr_v3,
    signature_size: u32,
};

pub const vendor_boot_img_hdr_v3 = extern struct {
    magic: [VENDOR_BOOT_MAGIC_SIZE]u8,
    header_version: u32,
    page_size: u32,
    kernel_addr: u32,
    ramdisk_addr: u32,
    vendor_ramdisk_size: u32,
    cmdline: [VENDOR_BOOT_ARGS_SIZE]u8,
    tags_addr: u32,
    name: [VENDOR_BOOT_NAME_SIZE]u8,
    header_size: u32,
    dtb_size: u32,
    dtb_addr: u64,
};

pub const vendor_boot_img_hdr_v4 = extern struct {
    base: vendor_boot_img_hdr_v3,
    vendor_ramdisk_table_size: u32,
    vendor_ramdisk_table_entry_num: u32,
    vendor_ramdisk_table_entry_size: u32,
    bootconfig_size: u32,
};

pub const vendor_ramdisk_table_entry_v4 = extern struct {
    ramdisk_size: u32,
    ramdisk_offset: u32,
    ramdisk_type: u32,
    ramdisk_name: [VENDOR_RAMDISK_NAME_SIZE]u8,
    board_id: [VENDOR_RAMDISK_TABLE_ENTRY_BOARD_ID_SIZE]u32,
};
