const std = @import("std");
const c = @import("c_api.zig");

pub fn fromCStructsToArrayList(from_array: anytype, from_array_length: i32, comptime ToType: type, allocator: std.mem.Allocator) !std.ArrayList(ToType) {
    const len: usize = @intCast(from_array_length);
    var arr = try std.ArrayList(ToType).initCapacity(allocator, len);
    {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const elem = blk: {
                const elem = ToType.initFromC(from_array[i]);
                break :blk switch (comptime @typeInfo(@TypeOf(elem))) {
                    .ErrorUnion => try elem,
                    else => elem,
                };
            };
            try arr.append(elem);
        }
    }
    return arr;
}

//  note: cannot implicitly cast double pointer '[*c]?*anyopaque' to anyopaque pointer '?*anyopaque'
pub fn ensurePtrNotNull(ptr: anytype) !@TypeOf(ptr) {
    if (ptr == null) return error.AllocationError;
    return ptr.?;
}

pub fn ensureFileExists(path: []const u8, allow_zero_byte: bool) !void {
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("File not found: {s}\n", .{path});
            return error.FileNotFound;
        },
        else => return err,
    };
    if (stat.size == 0 and !allow_zero_byte) {
        std.debug.print("File is empty: {s}\n", .{path});
        return error.FileEmpty;
    }
}

pub fn downloadFile(url: []const u8, dir: []const u8, allocator: std.mem.Allocator) !void {
    if (dir[dir.len - 1] != '/') unreachable;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var split_url = std.mem.split(u8, url, "/");
    var filename: []const u8 = undefined;
    while (split_url.next()) |s| {
        filename = s;
    }
    const dir_filename = try std.fmt.allocPrint(
        arena_allocator,
        "{s}{s}",
        .{ dir, filename },
    );
    var child = std.ChildProcess.init(
        &.{
            "curl",
            url,
            "-Lo",
            dir_filename,
            "--create-dirs",
        },
        arena_allocator,
    );
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    ensureFileExists(dir_filename, false) catch |err| switch (err) {
        error.FileNotFound, error.FileEmpty => {
            _ = try child.spawnAndWait();
            return;
        },
        else => return err,
    };
}

test "ensureNotNull" {
    var ptr: ?*u8 = null;
    try std.testing.expectError(error.AllocationError, ensurePtrNotNull(ptr));
}
