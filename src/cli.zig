const std = @import("std");
const clap = @import("clap");

const debug = std.debug;
const io = std.io;

pub const ServerConfig = struct { port: u16, cert: []const u8, private_key: []const u8, dir: []const u8, database: []const u8, access_log: []const u8 };

const CommandLineError = error{NoArgument};

pub fn parseArgs() !ServerConfig {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\--cert <str>           Public certificate.
        \\--private_key <str>    Private key.
        \\--dir <str>            Directory to serve.
        \\--port <u16>           Port to listen on.
        \\--database <str>       SQLite database to store traffic logs.
        \\--access_log <str>     Access log file from which to read remote addresses.
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

    const port = if (res.args.port) |p| p else 1965;
    const cert = if (res.args.cert) |c| c else return CommandLineError.NoArgument;
    const private_key = if (res.args.private_key) |k| k else return CommandLineError.NoArgument;
    const dir = if (res.args.dir) |d| d else ".";
    const database = if (res.args.database) |d| d else "cozroe.sqlite";
    const access_log = if (res.args.access_log) |l| l else "/tmp/cozroe.gemini.access";

    return .{ .port = port, .cert = cert, .private_key = private_key, .dir = dir, .database = database, .access_log = access_log };
}
