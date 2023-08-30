const std = @import("std");

pub const CliErrors = error{
    UnknownArgument,
    TooManyArguments,
    TooFewArguments,
    FlagMissingValue,
};

fn unknownArgument(arg: ArgInfo) !void {
    const flag = if (arg.named_flag) "--" else if (arg.flag) "-" else "";
    try std.io.getStdErr().writer().print(
        "Unknown argument: {s}{s}",
        .{ flag, arg.value },
    );
    return CliErrors.UnknownArgument;
}

pub fn Iterator(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize = 0,
        pub fn init(items: []const T) @This() {
            return .{ .data = items };
        }
        pub fn next(self: *@This()) ?T {
            if (self.index < self.data.len) {
                const v = self.data[self.index];
                self.index += 1;
                return v;
            }
            return null;
        }
        pub fn peek(self: *const @This()) ?T {
            if (self.index < self.data.len) {
                return self.data[self.index + 1];
            }
            return null;
        }
        pub fn reset(self: *@This()) void {
            self.index = 0;
        }
    };
}

const StringIterator = Iterator([]const u8);

pub const ArgInfo = struct {
    flag: bool = false,
    named_flag: bool = false,
    positional: bool = false,
    value: []const u8 = "",
    pub fn is(self: *const ArgInfo, short: u8, long: []const u8) bool {
        return short == self.value[0] or
            std.mem.eql(u8, long, self.value);
    }
};

pub const ArgParser = struct {
    args: *StringIterator,
    current: []const u8 = "",
    index: usize = 0,
    in_flag: bool = false,

    pub fn init(args: *StringIterator) ArgParser {
        return .{ .args = args };
    }

    pub fn nextPositional(self: *ArgParser) !ArgInfo {
        var arg = self.next() orelse return CliErrors.TooFewArguments;
        if (arg.flag) return CliErrors.FlagMissingValue;
        return arg;
    }

    pub fn next(self: *ArgParser) ?ArgInfo {
        if (self.index >= self.current.len) {
            // reset
            self.in_flag = false;
            self.index = 0;
            // get a new argument
            self.current = self.args.next() orelse return null;
            // check what kind of argument we are dealing with
            if (self.current[0] == '-' and self.current.len > 1) {
                if (self.current[1] == '-') {
                    // named flag
                    const end =
                        std.mem.indexOf(u8, self.current, "=") orelse self.current.len;
                    const arg = .{
                        .flag = true,
                        .named_flag = true,
                        // trim off the dashes
                        .value = self.current[2..end],
                    };
                    // step past the equals if there is one
                    self.index += end + 1;
                    return arg;
                }
                self.in_flag = true;
                // trim off dash
                self.current = self.current[1..];
            }
        }
        if (self.in_flag) {
            // short flag
            self.index += 1;
            const flag = self.current[self.index - 1 .. self.index];
            return .{ .flag = true, .value = flag };
        }
        // positional argument
        const arg = .{
            .positional = true,
            .value = self.current[self.index..self.current.len],
        };
        self.index = self.current.len;
        return arg;
    }
};

pub const Arguments = struct {
    port: u16 = 1965,
    certificate_path: ?[]const u8 = null,
    private_key_path: ?[]const u8 = null,
    directory: []const u8 = ".",
};

fn parseFromIterator(iterator: *StringIterator) !Arguments {
    var out = std.io.getStdErr().writer();
    var args = Arguments{};

    var arg_parser = ArgParser.init(iterator);
    while (arg_parser.next()) |arg| {
        if (arg.flag) {
            if (arg.is(0, "cert")) {
                args.certificate_path =
                    (try arg_parser.nextPositional()).value;
            } else if (arg.is(0, "key")) {
                args.private_key_path =
                    (try arg_parser.nextPositional()).value;
            } else if (arg.is(0, "dir")) {
                args.directory =
                    (try arg_parser.nextPositional()).value;
            } else if (arg.is(0, "port")) {
                args.port = try std.fmt.parseInt(
                    u16,
                    (try arg_parser.nextPositional()).value,
                    10,
                );
            } else {
                try unknownArgument(arg);
            }
        } else {
            try unknownArgument(arg);
        }
    }
    if (args.certificate_path == null) {
        _ = try out.write("Certificate path not specified (--cert)");
        std.os.exit(1);
    } else if (args.private_key_path == null) {
        _ = try out.write("Private key path not set (--key)");
        std.os.exit(1);
    }

    return args;
}

fn testArgParse(items: []const []const u8, comptime expected: Arguments) !void {
    var itt = StringIterator.init(items);
    const args = try parseFromIterator(&itt);
    try std.testing.expectEqualDeep(expected, args);
}

test "arg-parsing" {
    try testArgParse(
        &[_][]const u8{ "--cert", "cert.pem", "--key", "key.rsa" },
        .{
            .certificate_path = "cert.pem",
            .private_key_path = "key.rsa",
        },
    );
    try testArgParse(
        &[_][]const u8{ "--cert=cert.pem", "--key=key.rsa" },
        .{
            .certificate_path = "cert.pem",
            .private_key_path = "key.rsa",
        },
    );
}

pub fn parseArgs(
    allocator: std.mem.Allocator,
    iterator: *std.process.ArgIterator,
) !Arguments {
    var mem = std.heap.ArenaAllocator.init(allocator);
    defer mem.deinit();
    var alloc = mem.allocator();

    // convert to an iterator
    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();
    while (iterator.next()) |arg| {
        try list.append(arg);
    }

    // check for help
    var out = std.io.getStdOut().writer();
    var string_iterator = StringIterator.init(list.items);
    var arg_iterator = ArgParser.init(&string_iterator);
    while (arg_iterator.next()) |arg| {
        if (arg.is('h', "help")) {
            _ = try out.write(
                \\cozroe v0.2.0
                \\--help, -h         Display this help and exit.
                \\--dir <str>        Path to directory to serve.
                \\--cert <str>       Path to the server certificate.
                \\--key <str>        Path to the private key.
                \\--port, -p <int>   Port to listen on (default 1965).
                \\
            );
            // terminate after printing help
            std.os.exit(0);
        }
    }

    string_iterator.reset();
    return parseFromIterator(&string_iterator);
}
