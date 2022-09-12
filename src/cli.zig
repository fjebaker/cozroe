const std = @import("std");
const clap = @import("clap");

const debug = std.debug;
const io = std.io;

pub const ServerConfig = struct { port: u16, cert: []const u8, private_key: []const u8, dir: []const u8, database: []const u8 };

const CommandLineError = error{NoArgument};

pub fn parseArgs() !ServerConfig {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\--cert <str>       Public certificate.
        \\--private_key <str>       Private key.
        \\--dir <str>            Directory to serve.
        \\--port <u16>           Port to listen on.
        \\--database <str>       SQLite database to store traffic logs.
        \\
    );

    // Initalize our diagnostics, which can be used for reporting useful errors.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help) {
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        return CommandLineError.NoArgument;
    }

    var port = if (res.args.port) |p| p else 1965;
    var cert = if (res.args.cert) |c| c else return CommandLineError.NoArgument;
    var private_key = if (res.args.private_key) |k| k else return CommandLineError.NoArgument;
    var dir = if (res.args.dir) |d| d else ".";
    var database = if (res.args.database) |d| d else "cozroe.sqlite.db";

    return .{ .port = port, .cert = cert, .private_key = private_key, .dir = dir, .database = database };
}
