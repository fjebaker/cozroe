const std = @import("std");
const serve = @import("serve");
const network = @import("network");
const sqlite = @import("sqlite");

const gemfiles = @import("./gemfiles.zig");
const blueprint = @import("./blueprint.zig");
const parsing = @import("./file-parsing.zig");

const Regex = @import("regex").Regex;
const ServerConfig = @import("./cli.zig").ServerConfig;
const GeminiFile = gemfiles.GeminiFile;
const HomeGemFile = gemfiles.HomeGemFile;

const logger = std.log.scoped(.cozroe_server);

const SingleRequest = struct {
    path: []const u8,
    filepath: []const u8,
    time: i64,
    ip: ?[]const u8,
    context: *serve.GeminiContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, access_log_path: []const u8, context: *serve.GeminiContext) SingleRequest {
        const time: i64 = std.time.milliTimestamp();
        const path = context.request.url.path;
        const filepath = blueprint.getPage(path);

        const ip = parsing.getRemoteAddress(allocator, access_log_path);

        return SingleRequest{ .path = path, .filepath = filepath, .time = time, .ip = ip, .context = context, .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        if (self.ip) |ip| self.allocator.free(ip);
    }

    pub fn logToDatabase(self: *const @This(), db: *sqlite.Db) !void {
        const query =
            \\INSERT INTO traffic (time, ip, path) VALUES (?, ?, ?)
        ;
        if (self.ip) |ip| {
            var stmt = try db.prepare(query);
            defer stmt.deinit();
            try stmt.exec(.{}, .{ .time = self.time, .ip = ip, .path = self.path });
        } else {
            logger.info("no request logged to database since no remote address known", .{});
        }
    }
};

pub const Server = struct {
    config: *const ServerConfig,
    listener: serve.GeminiListener,
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    alive: bool,

    pub fn init(allocator: std.mem.Allocator, config: *const ServerConfig, db: *sqlite.Db) !Server {
        return Server{ .config = config, .listener = try serve.GeminiListener.init(allocator), .allocator = allocator, .db = db, .alive = false };
    }

    pub fn deinit(self: *@This()) void {
        self.listener.deinit();
    }

    pub fn start(self: *@This()) !void {
        try self.listener.addEndpoint(.{ .ipv4 = .{ 0, 0, 0, 0 } }, self.config.port, self.config.cert, self.config.private_key);
        try self.listener.start();
        defer self.listener.stop();

        self.alive = true;
        logger.info("cozroe server ready", .{});

        while (self.alive) {
            self.acceptConnection() catch |err| {
                logger.err("{}", .{err});
            };
        }
    }

    pub fn acceptConnection(self: *@This()) !void {
        var context = try self.listener.getContext();
        defer context.deinit();

        var req = SingleRequest.init(self.allocator, self.config.access_log, context);
        defer req.deinit();
        req.logToDatabase(self.db) catch |err| {
            logger.err("failed to write to database: {}", .{err});
        };

        // fulfill the request
        // get the file
        if (std.mem.eql(u8, req.filepath, "/index.gmi")) {
            var gf = try HomeGemFile.init(self.allocator, self.db, self.config.dir, req.filepath);
            defer gf.deinit();
            try gf.write(req.context);
        } else {
            var gf = try GeminiFile.init(self.allocator, self.config.dir, req.filepath);
            defer gf.deinit();
            try gf.write(req.context);
        }
    }
};
