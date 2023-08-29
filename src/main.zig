const std = @import("std");
const dedalus = @import("dedalus");

const log = std.log.scoped(.cozroe);

const cli = @import("cli.zig");

fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    return try file.readToEndAlloc(alloc, 65536);
}

fn serveFile(
    alloc: std.mem.Allocator,
    request: *dedalus.Request,
    path: []const u8,
) !void {
    var content = readFile(alloc, path) catch |err| {
        if (err != error.FileNotFound) {
            log.err("error: {!}", .{err});
        }
        try request.respond(.{ .status = .NOT_FOUND });
        return;
    };
    try request.respond(.{ .content = content });
}

fn handleRequest(request: *dedalus.Request) !void {
    defer request.deinit();

    var alloc = request.mem.allocator();

    // resolve request path
    if (std.mem.eql(u8, request.uri.path, "/")) {
        try serveFile(alloc, request, "index.gmi");
    } else {
        try serveFile(alloc, request, request.uri.path);
    }
}

fn listenForever(server: *dedalus.Server) !void {
    try server.start();
    defer server.stop();

    log.info("Server listening on {any}", .{server.address});

    while (true) {
        var request = server.accept() catch {
            continue;
        };
        try handleRequest(&request);
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    // process command line arguments
    var args_iterator = try std.process.argsWithAllocator(allocator);

    // drop program name
    _ = args_iterator.next();

    const args = try cli.parseArgs(allocator, &args_iterator);

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

    try listenForever(&server);
}

test "all" {
    _ = @import("cli.zig");
}
