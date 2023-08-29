const std = @import("std");
const dedalus = @import("dedalus");

const cli = @import("cli.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    // process command line arguments
    var args_iterator = try std.process.argsWithAllocator(allocator);
    // drop the name
    _ = args_iterator.next();
    const args = try cli.parseArgs(allocator, &args_iterator);
    _ = args;

    try dedalus.init();
    defer dedalus.deinit();
}
