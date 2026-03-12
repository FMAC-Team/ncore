const std = @import("std");
const linux = std.os.linux;
const syscall = std.os.linux.syscall3;

const log = @import("log.zig");
const build_options = @import("build_options");

const c = @cImport({
    @cInclude("sys/utsname.h");
    @cInclude("unistd.h");
    @cInclude("sys/system_properties.h");
});

var loadinfo: bool = false;

pub fn loadDeviceInfo(fd: i32) void {
    if (loadinfo == true) return;
    const u = getUnameInfo() catch |err| {
        log.info_f("failed to get uname: {}", .{err});
        return;
    };
    const buf = std.fmt.allocPrint(std.heap.page_allocator, "Kernel Info: {s}{s}{s}{s}{s}\n", .{ u.sysname, u.nodename, u.release, u.version, u.machine }) catch |err| {
        log.info_f("failed to format uname: {}", .{err});
        return;
    };
    const departline = "\n-------------------\n\n";
    selfVersion(fd);
    getPropInfo(fd, "Product name: ", "ro.product.odm.name");
    getPropInfo(fd, "Android version: ", "ro.build.version.release");
    _ = c.write(fd, buf.ptr, buf.len);
    _ = c.write(fd, departline.ptr, departline.len);
    std.heap.page_allocator.free(buf);
    loadinfo = true;
}

fn getPropInfo(fd: i32, tag: []const u8, prop: []const u8) void {
    var buf: [c.PROP_VALUE_MAX]u8 = undefined;
    const line = "\n";

    const len = c.__system_property_get(
        @ptrCast(prop.ptr),
        @ptrCast(&buf),
    );

    if (len <= 0) {
        log.info_f("get prop failed: {}", .{len});
        return;
    }

    _ = std.posix.write(fd, tag) catch |err| {
        log.info_f("write prop failed: {s}", .{@errorName(err)});
        return;
    };

    if (c.write(fd, @ptrCast(&buf), @intCast(len)) < 0) {
        log.info("write prop failed");
    }
    if (c.write(fd, line.ptr, line.len) < 0)
        log.info("write prop failed");
}

fn selfVersion(fd: i32) void {
    const version = build_options.version;
    const tag = "libncore version: ";
    const line = "\n";
    _ = c.write(fd, tag.ptr, tag.len);
    _ = c.write(fd, version.ptr, version.len);
    _ = c.write(fd, line.ptr, line.len);
}

fn getUnameInfo() !c.struct_utsname {
    var u: c.struct_utsname = undefined;

    const rc = linux.syscall1(
        .uname,
        @intFromPtr(&u),
    );

    if (@as(isize, @bitCast(rc)) < 0) {
        return error.UnameFailed;
    }

    return u;
}
