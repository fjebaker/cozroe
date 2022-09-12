const std = @import("std");
const serve = @import("serve");
const network = @import("network");
const sqlite = @import("sqlite");
const regex = @import("regex");

const Regex = regex.Regex;

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

    var re = try Regex.compile(allocator, "_remote_addr=([\\.\\d]*)");
    defer re.deinit();

    const query_string = context.request.url.query orelse "";
    logger.info("query: {s}", .{query_string});

    var caps = (try re.captures(query_string));
    defer if (caps) |*c| c.*.deinit();

    // database logging
    if (caps) |c| {
        var addr = c.sliceAt(1).?;
        logger.info("storing unpacked address: {s}", .{addr});
        try logToDatabase(db, addr, requested_path);
    }

    // blueprint for the site
    if (std.mem.eql(u8, requested_path, "/")) {
        const path = try std.fmt.allocPrint(allocator, "{s}/index.gmi", .{dir});
        defer allocator.free(path);

        try serveMainPage(allocator, context, db, path);
    } else {
        const path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir, requested_path });
        defer allocator.free(path);

        try serveFile(allocator, context, path);
    }
}

fn logToDatabase(db: *sqlite.Db, ip: []const u8, path: []const u8) !void {
    const query =
        \\INSERT INTO traffic (time, ip, dest) VALUES (?, ?, ?)
    ;
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{ .time = std.time.milliTimestamp(), .ip = ip, .dest = path });
}

const FileContent = struct {
    content: []const u8,
    allocator: std.mem.Allocator,

    pub fn free(self: *@This()) void {
        self.allocator.free(self.content);
    }

    pub fn write(self: *const @This(), context: *serve.GeminiContext) !void {
        try context.response.setStatusCode(.success);
        try context.response.setMeta("text/gemini");
        var stream = try context.response.writer();
        try stream.writeAll(self.content);
    }
};

fn readFileContent(allocator: std.mem.Allocator, path: []const u8) !FileContent {
    logger.debug("opening file '{s}'", .{path});
    var file = try std.fs.cwd().openFile(path, .{ .mode = std.fs.File.OpenMode.read_only });
    defer file.close();

    const read_buf = try file.readToEndAlloc(allocator, 65536);
    return .{ .content = read_buf, .allocator = allocator };
}

fn serveFile(allocator: std.mem.Allocator, context: *serve.GeminiContext, path: []const u8) !void {
    var file = try readFileContent(allocator, path);
    defer file.free();
    try file.write(context);
}

fn getOneDb(db: *sqlite.Db, comptime query: []const u8) !usize {
    const info = try db.one(usize, query, .{}, .{});
    if (info) |res| {
        return res;
    }
    logger.warn("No traffic in database?", .{});
    return 0;
}

fn getTotalConnectionsCount(db: *sqlite.Db) !usize {
    const query =
        \\ SELECT COUNT(ip) FROM traffic
    ;
    return try getOneDb(db, query);
}

fn getUniqueConnectionsCount(db: *sqlite.Db) !usize {
    const query =
        \\ SELECT COUNT(DISTINCT ip) AS uniques FROM traffic
    ;
    return try getOneDb(db, query);
}

fn serveMainPage(allocator: std.mem.Allocator, context: *serve.GeminiContext, db: *sqlite.Db, path: []const u8) !void {
    var file = try readFileContent(allocator, path);
    defer file.free();

    const count = try getTotalConnectionsCount(db);
    const count_string = try std.fmt.allocPrint(allocator, "{d}", .{count});
    defer allocator.free(count_string);

    const unique_count = try getUniqueConnectionsCount(db);
    const unique_count_string = try std.fmt.allocPrint(allocator, "{d}", .{unique_count});
    defer allocator.free(unique_count_string);

    // really bad way of doing this
    // would ideally calculate the total size of the array needed, and then
    // keep replacing into it
    // but this works for now
    var temp = try replaceString(allocator, file.content, "{{signal_count}}", count_string);
    defer allocator.free(temp);

    var output = try replaceString(allocator, temp, "{{signal_unique}}", unique_count_string);
    defer allocator.free(output);

    try context.response.setStatusCode(.success);
    try context.response.setMeta("text/gemini");
    var stream = try context.response.writer();
    try stream.writeAll(output);
}

fn replaceString(allocator: std.mem.Allocator, src: []const u8, needle: []const u8, target: []const u8) ![]const u8 {
    const size = std.mem.replacementSize(u8, src, needle, target);
    var output = try std.ArrayList(u8).initCapacity(allocator, size);
    output.expandToCapacity();
    _ = std.mem.replace(u8, src, needle, target, output.items);
    return output.toOwnedSlice();
}
