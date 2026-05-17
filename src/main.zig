const std = @import("std");
const bgg_tui = @import("bgg_tui");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const config_path = bgg_tui.config.resolveConfigPath(allocator, init.environ_map) catch |err| switch (err) {
        error.MissingConfigDirectory => null,
        else => return err,
    };
    const loaded_config = if (config_path) |path|
        try bgg_tui.config.loadConfig(allocator, init.io, path, init.environ_map)
    else
        bgg_tui.config.LoadedConfig{ .config = bgg_tui.config.Config.fromEnvironment(init.environ_map) };
    const config = loaded_config.config;

    std.debug.print("{s} {s}\n", .{ bgg_tui.name, bgg_tui.version });
    std.debug.print("Zig port scaffold is ready.\n", .{});
    std.debug.print("BGG API token: {s}\n", .{if (config.apiClientToken() == null) "missing" else "configured"});
}
