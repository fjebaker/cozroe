const std = @import("std");
const serve = @import("serve");
const network = @import("network");
const sqlite = @import("sqlite");

const cli = @import("./cli.zig");

const logger = std.log.scoped(.cozroe_server);

pub fn start(allocator: std.mem.Allocator, db: *sqlite.Db, config: cli.ServerConfig) !void {
    var listener = try serve.GeminiListener.init(allocator);
    defer listener.deinit();

    try listener.addEndpoint(.{ .ipv4 = .{ 0, 0, 0, 0 } }, config.port, config.cert, config.private_key);

    try listener.start();
    defer listener.stop();

    logger.info("gemini server ready.", .{});

    while (true) {
        acceptConnection(allocator, &listener, db, config.dir) catch |err| {
            logger.err("{}", .{err});
        };
    }
}

fn acceptConnection(allocator: std.mem.Allocator, listener: *serve.GeminiListener, db: *sqlite.Db, dir: []const u8) !void {
    var context = try listener.getContext();
    defer context.deinit();

    const requested_path = context.request.url.path;

    var ip = try std.fmt.allocPrint(allocator, "{s}/index.gmi", .{dir});
    defer allocator.free(ip);

    try logToDatabase(db, ip, requested_path);

    const path = if (std.mem.eql(u8, requested_path, "/"))
        try std.fmt.allocPrint(allocator, "{s}/index.gmi", .{dir})
    else
        try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir, requested_path });
    defer allocator.free(path);

    serveFile(allocator, context, path) catch |err| {
        logger.err("{}", .{err});
    };
}

fn logToDatabase(db: * sqlite.Db, ip: [] const u8, path: [] const u8) !void {
    const query = 
        \\INSERT INTO traffic (time, ip, dest) VALUES (?, ?, ?)
    ; 
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{ .time = std.time.milliTimestamp(), .ip = ip, .dest = path });
}

fn serveFile(allocator: std.mem.Allocator, context: *serve.GeminiContext, path: []const u8) !void {
    logger.debug("opening file '{s}'", .{path});
    var file = try std.fs.cwd().openFile(path, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();

    const read_buf = try file.readToEndAlloc(allocator, 65536);
    defer allocator.free(read_buf);

    try context.response.setStatusCode(.success);
    try context.response.setMeta("text/gemini");
    var stream = try context.response.writer();
    try stream.writeAll(read_buf);
}
