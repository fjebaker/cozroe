const std = @import("std");

const logger = std.log.scoped(.cozroe_parsing);

pub fn getLatestEntry(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    logger.debug("reading access log '{s}'", .{path});

    var file = try std.fs.cwd().openFile(path, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();

    const read_buf = try file.readToEndAlloc(allocator, 1048576); // 1 mebibyte
    defer allocator.free(read_buf);

    // find index of last line
    var n1: usize = 0;
    var n2: usize = 0;
    for (read_buf) |char, index| {
        if (char == '\n') {
            if (index == read_buf.len) {
                // at the end of the file
                if (n2 - index <= 1) {
                    // have blank new line
                    break;
                }
            }
            n1 = n2 + 1;
            n2 = index;
        }
    }

    // allocate and return
    const slice = try allocator.alloc(u8, n2 - n1);
    std.mem.copy(u8, slice, read_buf[n1..n2]);
    return slice;
}

pub fn getRemoteAddress(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const entry = getLatestEntry(allocator, path) catch |err| {
        logger.err("error reading access log: {}", .{err});
        return null;
    };
    defer allocator.free(entry);

    var last_delim = std.mem.lastIndexOfScalar(u8, entry, '|') orelse {
        logger.err("could not find delimeter in: {s}", .{entry});
        return null;
    };
    last_delim += 1;

    const slice = allocator.alloc(u8, entry.len - last_delim) catch |err| {
        logger.err("allocation error: {}", .{err});
        return null;
    };
    std.mem.copy(u8, slice, entry[last_delim..entry.len]);

    logger.info("parsed remote address: {s}", .{slice});

    return slice;
}
