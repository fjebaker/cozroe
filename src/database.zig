const std = @import("std");
const sqlite = @import("sqlite");

const logger = std.log.scoped(.cozroe_database);

pub fn init(path: [:0]const u8) !sqlite.Db {
    logger.debug("using {s}", .{path});
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });

    const query =
        \\ CREATE TABLE IF NOT EXISTS traffic(time INTEGER PRIMARY KEY, ip TEXT NOT NULL, path TEXT NOT NULL)
    ;
    try db.exec(query, .{}, .{});
    return db;
}

pub fn getOneDb(db: *sqlite.Db, comptime query: []const u8) !usize {
    const info = try db.one(usize, query, .{}, .{});
    if (info) |res| {
        return res;
    }
    logger.warn("No traffic in database?", .{});
    return 0;
}

pub fn getTotalConnectionsCount(db: *sqlite.Db) !usize {
    const query =
        \\ SELECT COUNT(ip) FROM traffic
    ;
    return try getOneDb(db, query);
}

pub fn getUniqueConnectionsCount(db: *sqlite.Db) !usize {
    const query =
        \\ SELECT COUNT(DISTINCT ip) AS uniques FROM traffic
    ;
    return try getOneDb(db, query);
}
