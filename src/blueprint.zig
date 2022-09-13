const std = @import("std");

pub fn getPage(path: [] const u8) [] const u8 {
    if (std.mem.eql(u8, path, "/")) {
        return "/index.gmi";
    } else {
        return path;
    }
}