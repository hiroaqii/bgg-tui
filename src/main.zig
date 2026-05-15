const std = @import("std");
const bgg_tui = @import("bgg_tui");

pub fn main() !void {
    std.debug.print("{s} {s}\n", .{ bgg_tui.name, bgg_tui.version });
    std.debug.print("Zig port scaffold is ready.\n", .{});
}
