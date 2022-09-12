const std = @import("std");
const sqlite = @import("sqlite");

const logger = std.log.scoped(.cozroe_database);

pub fn init(path: [:0] const u8) !sqlite.Db {
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
        \\ CREATE TABLE IF NOT EXISTS traffic(time INTEGER PRIMARY KEY, ip TEXT NOT NULL, dest TEXT NOT NULL)
    ;
    try db.exec(query, .{}, .{});
    return db;
}