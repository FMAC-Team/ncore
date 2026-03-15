const std = @import("std");
const fs = std.fs;
const elf = std.elf;
const posix = std.posix;

// logic by kernelsu init

fn normalizeSymbol(sym: []const u8) []const u8 {
    if (std.mem.indexOf(u8, sym, "$")) |pos| {
        return sym[0..pos];
    }
    if (std.mem.indexOf(u8, sym, ".llvm.")) |pos| {
        return sym[0..pos];
    }
    return sym;
}

fn parseKallsyms(allocator: std.mem.Allocator) !std.StringHashMap(u64) {
    var map = std.StringHashMap(u64).init(allocator);
    try map.ensureTotalCapacity(400000);

    const file = try std.fs.openFileAbsolute("/proc/kallsyms", .{});
    defer file.close();
    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;

        const s1 = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const s2 = std.mem.indexOfScalarPos(u8, line, s1 + 1, ' ') orelse continue;

        const addr = hexTou64(line[0..s1]) orelse continue;
        const name = line[s2 + 1 ..];
        const name_copy = try allocator.dupe(u8, name);
        try map.put(name_copy, addr);
    }

    return map;
}

fn hexTou64(s: []const u8) ?u64 {
    if (s.len > 16) return null;
    var v: u64 = 0;
    for (s) |c| {
        v <<= 4;
        v |= switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
    }
    return v;
}

fn patch_and_load(
    allocator: std.mem.Allocator,
    path: []const u8,
    kallsyms: *std.StringHashMap(u64),
) !i32 {
    var file = fs.cwd().openFile(path, .{ .mode = .read_write }) catch return -1;
    defer file.close();

    const file_size = try file.getEndPos();

    var image = allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(@alignOf(elf.Elf64_Ehdr)), file_size) catch return -1;
    defer allocator.free(image);

    _ = try file.readAll(image);

    if (image.len < @sizeOf(elf.Elf64_Ehdr)) return -1;
    const ehdr = @as(*elf.Elf64_Ehdr, @ptrCast(image.ptr));

    if (!std.mem.eql(u8, ehdr.e_ident[0..4], "\x7fELF")) return -1;

    const shdrs_ptr = @as([*]elf.Elf64_Shdr, @ptrCast(@alignCast(&image[ehdr.e_shoff])));
    const shdrs = shdrs_ptr[0..ehdr.e_shnum];

    var symtab_shdr: ?*elf.Elf64_Shdr = null;
    for (shdrs) |*shdr| {
        if (shdr.sh_type == elf.SHT_SYMTAB) {
            symtab_shdr = shdr;
            break;
        }
    }

    const sym_shdr = symtab_shdr orelse return -1;
    if (sym_shdr.sh_link >= ehdr.e_shnum) return -1;

    const strtab_shdr = &shdrs[sym_shdr.sh_link];
    const strtab = image[strtab_shdr.sh_offset .. strtab_shdr.sh_offset + strtab_shdr.sh_size];

    const sym_count = sym_shdr.sh_size / sym_shdr.sh_entsize;
    const syms_ptr = @as([*]elf.Elf64_Sym, @ptrCast(@alignCast(&image[sym_shdr.sh_offset])));
    const syms = syms_ptr[0..sym_count];

    for (syms) |*sym| {
        if (sym.st_shndx == elf.SHN_UNDEF and sym.st_name != 0) {
            if (sym.st_name >= strtab.len) continue;

            const name = normalizeSymbol(std.mem.sliceTo(strtab[sym.st_name..], 0));

            if (kallsyms.get(name)) |addr| {
                std.debug.print("Patching symbol {s} -> 0x{x}\n", .{ name, addr });
                sym.st_value = addr;
                sym.st_shndx = elf.SHN_ABS;
            } else {
                std.log.warn("missing symbol: {s}", .{name});
                std.log.warn("rejection!", .{});
                return -1;
            }
        }
    }
    const ret = try loadModule(@intFromPtr(image.ptr), image.len);
    return ret;
}

fn loadModule(image_ptr: usize, image_len: usize) !i32 {
    const params: []const u8 = "";
    const ret = std.os.linux.syscall3(
        .init_module,
        image_ptr,
        image_len,
        @intFromPtr(params.ptr),
    );

    const signed_ret: isize = @bitCast(ret);
    if (signed_ret < 0) {
        return -1;
    }

    return @as(i32, @intCast(signed_ret));
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var kallsyms = try parseKallsyms(arena_alloc);
    _ = patch_and_load(allocator, path, &kallsyms) catch {
        return;
    };
}
