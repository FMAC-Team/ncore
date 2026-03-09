const std = @import("std");
const linux = std.os.linux;

const log = @import("log.zig");

const c = @cImport({
    @cInclude("sys/utsname.h");
        @cInclude("unistd.h");
});

var loadinfo: usize = 0;

pub fn loadDeviceInfo(fd: i32) void {
    if (loadinfo != 0) return;
    const u = getUnameInfo() catch |err| {
        log.info_f("failed to get uname: {}", .{err});
        return;
    };
    const buf = std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}{s}{s}\n", .{ u.sysname, u.nodename, u.release, u.version, u.machine }) catch |err| {
        log.info_f("failed to format uname: {}", .{err});
        return;
    };
    _ = c.write(fd, buf.ptr, buf.len);
    std.heap.page_allocator.free(buf);
    loadinfo=1;
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
