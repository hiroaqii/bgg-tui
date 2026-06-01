const std = @import("std");
const chasen = @import("chasen");
const chasen_graphics_chasen = @import("chasen_graphics_chasen");
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
    const image_cache_dir = bgg_tui.image.resolveCacheDir(allocator, init.environ_map) catch |err| switch (err) {
        error.MissingCacheDirectory => null,
        else => return err,
    };

    // Terminal image support stays optional: app code decides when to load an
    // image, while Chasen owns local path -> terminal image handle conversion.
    // Use the decoded loader so chasen-graphics can handle JPEG cover art
    // before terminal transport.
    const image_loader: ?chasen.TerminalImagePathLoaderFn = if (config.display.show_images and config.display.image_protocol != .off)
        chasen_graphics_chasen.decodedImagePathLoader
    else
        null;

    try chasen.runWith(.{
        .runtime = .{
            .allocator = init.gpa,
            .io = init.io,
        },
        .terminal = .{
            .env_map = init.environ_map,
            .image_path_loader = image_loader,
        },
    }, bgg_tui.app.App.create(config, .{
        .config_path = config_path,
        .image_cache_dir = image_cache_dir,
    }));
}
