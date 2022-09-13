const std = @import("std");
const serve = @import("serve");
const sqlite = @import("sqlite");

const database = @import("./database.zig");

const logger = std.log.scoped(.cozroe_gemfiles);

pub fn BaseGemFile(comptime Super: type, comptime finalize: *const fn (super: *Super, content: []const u8) ?[]const u8) type {
    return struct {
        super: Super,
        content: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, super: Super, dir: []const u8, path: []const u8) !@This() {
            const content = try @This().readFromDir(allocator, dir, path);
            return .{
                .super = super,
                .content = content,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.content);
            self.super.deinit();
        }

        pub fn write(self: *@This(), context: *serve.GeminiContext) !void {
            try context.response.setStatusCode(.success);
            try context.response.setMeta("text/gemini");
            var stream = try context.response.writer();
            if (finalize(&self.super, self.content)) |content| {
                try stream.writeAll(content);
                defer self.allocator.free(content);
            } else {
                try stream.writeAll(self.content);
            }
        }

        fn read(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
            logger.debug("opening file '{s}'", .{path});
            var file = try std.fs.cwd().openFile(path, .{ .mode = std.fs.File.OpenMode.read_only });
            defer file.close();
            return try file.readToEndAlloc(allocator, 65536);
        }

        fn readFromDir(allocator: std.mem.Allocator, dir: []const u8, path: []const u8) ![]const u8 {
            const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir, path });
            defer allocator.free(full_path);
            return try @This().read(allocator, full_path);
        }
    };
}

pub const GeminiFile = struct {
    const Self = @This();
    const GemFile = BaseGemFile(Self, Self.noFinalize);

    pub fn init(allocator: std.mem.Allocator, dir: []const u8, path: []const u8) !GemFile {
        const self: Self = .{};
        return try GemFile.init(allocator, self, dir, path);
    }

    pub fn deinit(_: *Self) void {}

    fn noFinalize(_: *Self, _: []const u8) ?[]const u8 {
        return null;
    }
};

pub const HomeGemFile = struct {
    const Self = @This();
    const GemFile = BaseGemFile(Self, Self.substitute);

    db: * sqlite.Db,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db: * sqlite.Db, dir: []const u8, path: []const u8) !GemFile {
        const self: Self = .{.db = db, .allocator = allocator};
        return try GemFile.init(allocator, self, dir, path);
    }

    pub fn deinit(_: *Self) void {}

    fn substitute(self: * Self, content: [] const u8) ?[] const u8 {
        const count: usize = database.getTotalConnectionsCount(self.db) catch 0;
        const unique_count: usize = database.getUniqueConnectionsCount(self.db) catch 0;

        const count_string = std.fmt.allocPrint(self.allocator, "{d}", .{count}) catch "0";
        defer self.allocator.free(count_string);

        const unique_count_string = std.fmt.allocPrint(self.allocator, "{d}", .{unique_count}) catch "0";
        defer self.allocator.free(unique_count_string);

        // really bad way of doing this
        // would ideally calculate the total size of the array needed, and then
        // keep replacing into it
        // but this works for now
        var temp = replaceString(self.allocator, content, "{{signal_count}}", count_string) catch null;
        defer if (temp) |t| self.allocator.free(t);

        var output = replaceString(self.allocator, temp orelse content, "{{signal_unique}}", unique_count_string) catch null;
        return output;
    }
};

fn replaceString(allocator: std.mem.Allocator, src: []const u8, needle: []const u8, target: []const u8) ![]const u8 {
    const size = std.mem.replacementSize(u8, src, needle, target);
    var output = try std.ArrayList(u8).initCapacity(allocator, size);
    output.expandToCapacity();
    _ = std.mem.replace(u8, src, needle, target, output.items);
    return output.toOwnedSlice();
}