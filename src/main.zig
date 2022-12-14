const std = @import("std");
const serve = @import("serve");
const network = @import("network");

const server = @import("./server.zig");
const cli = @import("./cli.zig");
const database = @import("./database.zig");

pub fn main() !void {
    // parse arguments
    var config = cli.parseArgs() catch return;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try network.init();
    defer network.deinit();

    try serve.initTls();
    defer serve.deinitTls();

    var alloc = gpa.allocator();

    var path = try std.mem.Allocator.dupeZ(alloc, u8, config.database);
    defer alloc.free(path);

    var db = try database.init(path);
    defer db.deinit();

    var s = try server.Server.init(alloc, &config, &db);
    defer s.deinit();

    try s.start();
}
