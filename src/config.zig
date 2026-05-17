const std = @import("std");
const builtin = @import("builtin");

pub const config_path_env = "BGG_TUI_CONFIG_PATH";
pub const primary_token_env = "BGG_TUI_API_TOKEN";
pub const fallback_token_env = "BGG_API_TOKEN";
pub const app_dir_name = "bgg-tui";
pub const config_file_name = "config.toml";

pub const PathError = std.mem.Allocator.Error || error{
    MissingConfigDirectory,
};

pub const Config = struct {
    api: Api = .{},
    display: Display = .{},
    collection: Collection = .{},
    interface: Interface = .{},

    pub fn defaults() Config {
        return .{};
    }

    pub fn fromEnvironment(env: *const std.process.Environ.Map) Config {
        var config = defaults();
        config.api.token = tokenFromEnvironment(env);
        return config;
    }

    pub fn apiClientToken(config: Config) ?[]const u8 {
        return nonEmptyTrimmed(config.api.token);
    }
};

pub const Api = struct {
    token: ?[]const u8 = null,
};

pub const ImageProtocol = enum {
    auto,
    kitty,
    off,
};

pub const Display = struct {
    show_images: bool = true,
    image_protocol: ImageProtocol = .auto,
    list_width: u16 = 40,
    thread_width: u16 = 90,
    detail_width: u16 = 90,
};

pub const Collection = struct {
    default_username: ?[]const u8 = null,
    status_filter: CollectionStatus = .own,
};

pub const CollectionStatus = enum {
    own,
    prev_owned,
    for_trade,
    want,
    want_to_play,
    want_to_buy,
    wishlist,
    preordered,
};

pub const Interface = struct {
    color_theme: []const u8 = "default",
    transition: []const u8 = "none",
    selection: []const u8 = "none",
    list_density: []const u8 = "normal",
    date_format: []const u8 = "yyyy-mm-dd",
    border_style: []const u8 = "rounded",
};

/// Resolves the config file path without creating directories or files.
/// Explicit `BGG_TUI_CONFIG_PATH` wins; otherwise the path follows the host OS
/// config directory convention.
pub fn resolveConfigPath(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) PathError![]u8 {
    return try resolveConfigPathForOs(allocator, env, builtin.os.tag);
}

/// Reads the token from environment variables only. TOML loading will populate
/// the same `Config.api.token` field later, before the live API check runs.
pub fn tokenFromEnvironment(env: *const std.process.Environ.Map) ?[]const u8 {
    if (env.get(primary_token_env)) |value| {
        if (nonEmptyTrimmed(value)) |token| return token;
    }
    if (env.get(fallback_token_env)) |value| {
        if (nonEmptyTrimmed(value)) |token| return token;
    }
    return null;
}

fn resolveConfigPathForOs(
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    os_tag: std.Target.Os.Tag,
) PathError![]u8 {
    if (env.get(config_path_env)) |value| {
        if (nonEmptyTrimmed(value)) |path| return try allocator.dupe(u8, path);
    }

    return switch (os_tag) {
        .windows => {
            if (env.get("APPDATA")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinConfigPath(allocator, dir);
            }
            if (env.get("LOCALAPPDATA")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinConfigPath(allocator, dir);
            }
            return error.MissingConfigDirectory;
        },
        .macos => {
            const home = nonEmptyTrimmed(env.get("HOME")) orelse return error.MissingConfigDirectory;
            const app_support = try std.fs.path.join(allocator, &.{ home, "Library", "Application Support" });
            defer allocator.free(app_support);
            return try joinConfigPath(allocator, app_support);
        },
        else => {
            if (env.get("XDG_CONFIG_HOME")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinConfigPath(allocator, dir);
            }
            const home = nonEmptyTrimmed(env.get("HOME")) orelse return error.MissingConfigDirectory;
            const config_dir = try std.fs.path.join(allocator, &.{ home, ".config" });
            defer allocator.free(config_dir);
            return try joinConfigPath(allocator, config_dir);
        },
    };
}

fn joinConfigPath(allocator: std.mem.Allocator, config_root: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ config_root, app_dir_name, config_file_name });
}

fn nonEmptyTrimmed(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

test "config path uses explicit override when set" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(config_path_env, " /tmp/custom-bgg.toml ");
    try env.put("XDG_CONFIG_HOME", "/tmp/xdg");

    const path = try resolveConfigPathForOs(std.testing.allocator, &env, .linux);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/tmp/custom-bgg.toml", path);
}

test "config path uses XDG config home on unix-like systems" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("XDG_CONFIG_HOME", "/tmp/xdg");
    try env.put("HOME", "/tmp/home");

    const path = try resolveConfigPathForOs(std.testing.allocator, &env, .linux);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/tmp/xdg/bgg-tui/config.toml", path);
}

test "config path falls back to HOME config directory on unix-like systems" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/tmp/home");

    const path = try resolveConfigPathForOs(std.testing.allocator, &env, .linux);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/tmp/home/.config/bgg-tui/config.toml", path);
}

test "config path uses macOS application support directory" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/Users/tester");

    const path = try resolveConfigPathForOs(std.testing.allocator, &env, .macos);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/Users/tester/Library/Application Support/bgg-tui/config.toml", path);
}

test "config path errors when no config directory source exists" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    try std.testing.expectError(error.MissingConfigDirectory, resolveConfigPathForOs(std.testing.allocator, &env, .linux));
}

test "config defaults keep token unset and stable display values" {
    const config = Config.defaults();

    try std.testing.expectEqual(@as(?[]const u8, null), config.api.token);
    try std.testing.expectEqual(ImageProtocol.auto, config.display.image_protocol);
    try std.testing.expect(config.display.show_images);
    try std.testing.expectEqual(@as(u16, 40), config.display.list_width);
    try std.testing.expectEqual(CollectionStatus.own, config.collection.status_filter);
}

test "config loads primary API token environment variable" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(primary_token_env, " token-primary ");
    try env.put(fallback_token_env, "token-fallback");

    const config = Config.fromEnvironment(&env);

    try std.testing.expectEqualStrings("token-primary", config.apiClientToken().?);
}

test "config falls back to generic BGG API token environment variable" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(fallback_token_env, "token-fallback");

    const config = Config.fromEnvironment(&env);

    try std.testing.expectEqualStrings("token-fallback", config.apiClientToken().?);
}

test "config ignores empty API token environment variables" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(primary_token_env, " \n\t ");

    const config = Config.fromEnvironment(&env);

    try std.testing.expectEqual(@as(?[]const u8, null), config.apiClientToken());
}
