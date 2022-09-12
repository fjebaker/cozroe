const std = @import("std");
const clap = @import("clap");

const debug = std.debug;
const io = std.io;

pub const ServerConfig = struct { port: u16, pub_cert: []const u8, priv_key: []const u8, dir: []const u8, database: [] const u8 };

const CommandLineError = error{NoArgument};

pub fn parseArgs() !ServerConfig {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\--pub_cert <str>       Public certificate.
        \\--priv_key <str>       Private key.
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
    var pub_cert = if (res.args.pub_cert) |c| c else return CommandLineError.NoArgument; 
    var priv_key = if (res.args.priv_key) |k| k else return CommandLineError.NoArgument;
    var dir = if (res.args.dir) |d| d else ".";
    var database = if (res.args.database) |d| d else "cozroe.sqlite.db";

    return .{ .port = port, .pub_cert = pub_cert, .priv_key = priv_key, .dir = dir, .database = database};
}
