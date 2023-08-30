const std = @import("std");
const dedalus = @import("dedalus");

const log = std.log.scoped(.cozroe);

const cli = @import("cli.zig");

fn isValidFile(directory: []const u8, path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(directory, .{}) catch |err| {
        log.err("error opening {s} as dir:{!}", .{ directory, err });
        return false;
    };
    defer dir.close();

    var buf: [1024]u8 = undefined;
    var abspath = dir.realpath(path, &buf) catch {
        return false;
    };
    return std.mem.startsWith(u8, abspath, directory);
}

test "valid-files" {
    var buf: [1024]u8 = undefined;
    const root = try std.os.getcwd(&buf);
    try std.testing.expect(isValidFile(root, "./build.zig"));
    try std.testing.expect(isValidFile(root, "src/main.zig"));
    // // should fail
    try std.testing.expect(!isValidFile(root, ".."));
    try std.testing.expect(!isValidFile(root, "/dev"));
    try std.testing.expect(!isValidFile(root, "/file/that/doesnt/exist"));
    try std.testing.expect(!isValidFile(root, "./buiiiild.zig"));
}

const SandboxErrors = error{SandboxViolation};

fn readFile(alloc: std.mem.Allocator, directory: []const u8, path: []const u8) ![]u8 {
    if (!isValidFile(directory, path)) return SandboxErrors.SandboxViolation;
    var dir = try std.fs.openDirAbsolute(directory, .{});
    defer dir.close();
    return dir.readFileAlloc(alloc, path, 65536);
}

fn serveFile(
    alloc: std.mem.Allocator,
    request: *dedalus.Request,
    directory: []const u8,
    path: []const u8,
) !void {
    const adjusted_path = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;
    var content = readFile(alloc, directory, adjusted_path) catch |err| {
        if (err != error.FileNotFound and err != error.SandboxViolation) {
            log.err("error: {!}", .{err});
        }
        try request.respond(.{ .status = .NOT_FOUND });
        return;
    };
    try request.respond(.{ .content = content });
}

fn handleRequest(path: []const u8, request: *dedalus.Request) !void {
    defer request.deinit();

    var alloc = request.mem.allocator();

    // resolve request path
    if (std.mem.eql(u8, request.uri.path, "/")) {
        try serveFile(alloc, request, path, "index.gmi");
    } else {
        try serveFile(alloc, request, path, request.uri.path);
    }
}

fn listenForever(path: []const u8, server: *dedalus.Server) !void {
    try server.start();
    defer server.stop();

    log.info("Server listening on {any}", .{server.address});

    while (true) {
        var request = server.accept() catch {
            continue;
        };
        try handleRequest(path, &request);
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    // process command line arguments
    var args_iterator = try std.process.argsWithAllocator(allocator);

    // drop program name
    _ = args_iterator.next();

    const args = try cli.parseArgs(allocator, &args_iterator);

    // init the SSL library
    try dedalus.init();
    defer dedalus.deinit();

    const address = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, args.port);

    var certificate_path = try allocator.dupeZ(u8, args.certificate_path.?);
    defer allocator.free(certificate_path);
    var private_key_path = try allocator.dupeZ(u8, args.private_key_path.?);
    defer allocator.free(private_key_path);

    var server = try dedalus.Server.init(
        allocator,
        .{
            .address = address,
            .certificate = certificate_path,
            .private_key = private_key_path,
        },
    );
    defer server.deinit();

    var buf: [1024]u8 = undefined;
    const directory_path = try std.fs.cwd().realpath(args.directory, &buf);

    try listenForever(directory_path, &server);
}

test "all" {
    _ = @import("cli.zig");
}
