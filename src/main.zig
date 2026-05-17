const std = @import("std");
const bgg_tui = @import("bgg_tui");

pub fn main(init: std.process.Init) !void {
    const config = bgg_tui.config.Config.fromEnvironment(init.environ_map);

    std.debug.print("{s} {s}\n", .{ bgg_tui.name, bgg_tui.version });
    std.debug.print("Zig port scaffold is ready.\n", .{});
    std.debug.print("BGG API token: {s}\n", .{if (config.apiClientToken() == null) "missing" else "configured"});
}
