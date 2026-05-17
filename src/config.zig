const std = @import("std");

pub const primary_token_env = "BGG_TUI_API_TOKEN";
pub const fallback_token_env = "BGG_API_TOKEN";

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

fn nonEmptyTrimmed(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
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
