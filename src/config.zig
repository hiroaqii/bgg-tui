const std = @import("std");
const builtin = @import("builtin");

pub const config_path_env = "BGG_TUI_CONFIG_PATH";
pub const primary_token_env = "BGG_TUI_API_TOKEN";
pub const fallback_token_env = "BGG_API_TOKEN";
pub const app_dir_name = "bgg-tui";
pub const config_file_name = "config.toml";
pub const max_config_bytes = 256 * 1024;

pub const PathError = std.mem.Allocator.Error || error{
    MissingConfigDirectory,
};

pub const LoadError = std.Io.Dir.ReadFileAllocError || ParseError;
pub const SaveError = std.mem.Allocator.Error || std.Io.Dir.CreateDirPathError || std.Io.Dir.WriteFileError || error{
    InvalidConfigPath,
    UnsupportedStringValue,
    WriteFailed,
};

pub const ParseError = error{
    InvalidLine,
    InvalidSection,
    InvalidKeyValue,
    InvalidString,
    InvalidBool,
    InvalidInteger,
    InvalidEnum,
    UnknownSection,
    UnknownKey,
    UnsupportedEscape,
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

pub const LoadedConfig = struct {
    config: Config,
    source_bytes: ?[]u8 = null,

    pub fn deinit(loaded: *LoadedConfig, allocator: std.mem.Allocator) void {
        if (loaded.source_bytes) |bytes| allocator.free(bytes);
        loaded.* = undefined;
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

pub fn formatToml(allocator: std.mem.Allocator, config: Config) SaveError![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll(
        \\[api]
        \\token =
    );
    try out.writer.writeByte(' ');
    try writeTomlString(&out.writer, config.api.token orelse "");
    try out.writer.writeAll(
        \\
        \\
        \\[display]
        \\
    );
    try out.writer.print("show_images = {}\n", .{config.display.show_images});
    try out.writer.writeAll("image_protocol = ");
    try writeTomlString(&out.writer, @tagName(config.display.image_protocol));
    try out.writer.print(
        \\
        \\list_width = {d}
        \\thread_width = {d}
        \\detail_width = {d}
        \\
        \\
        \\[collection]
        \\default_username =
    , .{
        config.display.list_width,
        config.display.thread_width,
        config.display.detail_width,
    });
    try out.writer.writeByte(' ');
    try writeTomlString(&out.writer, config.collection.default_username orelse "");
    try out.writer.writeAll("\nstatus_filter = ");
    try writeTomlString(&out.writer, @tagName(config.collection.status_filter));
    try out.writer.writeAll(
        \\
        \\
        \\[interface]
        \\color_theme =
    );
    try out.writer.writeByte(' ');
    try writeTomlString(&out.writer, config.interface.color_theme);
    try out.writer.writeAll("\ntransition = ");
    try writeTomlString(&out.writer, config.interface.transition);
    try out.writer.writeAll("\nselection = ");
    try writeTomlString(&out.writer, config.interface.selection);
    try out.writer.writeAll("\nlist_density = ");
    try writeTomlString(&out.writer, config.interface.list_density);
    try out.writer.writeAll("\ndate_format = ");
    try writeTomlString(&out.writer, config.interface.date_format);
    try out.writer.writeAll("\nborder_style = ");
    try writeTomlString(&out.writer, config.interface.border_style);
    try out.writer.writeByte('\n');

    return try out.toOwnedSlice();
}

pub fn saveConfig(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    config: Config,
) SaveError!void {
    return try saveConfigToDir(allocator, io, .cwd(), path, config);
}

/// Loads config from disk when present, then applies environment overrides.
/// Missing files are not fatal because first launch is expected to start from
/// defaults before the setup/settings screens save a config file.
pub fn loadConfig(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    env: *const std.process.Environ.Map,
) LoadError!LoadedConfig {
    return try loadConfigFromDir(allocator, io, .cwd(), path, env);
}

/// Parses the fixed bgg-tui config schema from TOML-like input.
/// String values are borrowed from `input`; callers must keep the input buffer
/// alive for as long as the returned `Config` is used.
pub fn parseToml(input: []const u8) ParseError!Config {
    var config = Config.defaults();
    var section: Section = .root;

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |raw_line| {
        const line = trimWhitespaceAndComment(raw_line);
        if (line.len == 0) continue;

        if (line[0] == '[') {
            section = try parseSection(line);
            continue;
        }

        const separator_index = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidKeyValue;
        const key = std.mem.trim(u8, line[0..separator_index], " \t\r");
        const value = std.mem.trim(u8, line[separator_index + 1 ..], " \t\r");
        if (key.len == 0 or value.len == 0) return error.InvalidKeyValue;

        switch (section) {
            .root => return error.UnknownKey,
            .api => try parseApiValue(&config.api, key, value),
            .display => try parseDisplayValue(&config.display, key, value),
            .collection => try parseCollectionValue(&config.collection, key, value),
            .interface => try parseInterfaceValue(&config.interface, key, value),
        }
    }

    return config;
}

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

fn loadConfigFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    env: *const std.process.Environ.Map,
) LoadError!LoadedConfig {
    const bytes = dir.readFileAlloc(io, path, allocator, .limited(max_config_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .{ .config = Config.fromEnvironment(env) },
        else => |e| return e,
    };
    errdefer allocator.free(bytes);

    var config = try parseToml(bytes);
    applyEnvironmentOverrides(&config, env);

    return .{
        .config = config,
        .source_bytes = bytes,
    };
}

fn applyEnvironmentOverrides(config: *Config, env: *const std.process.Environ.Map) void {
    if (tokenFromEnvironment(env)) |token| {
        config.api.token = token;
    }
}

fn saveConfigToDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    config: Config,
) SaveError!void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len > 0) try dir.createDirPath(io, parent);
    } else if (std.fs.path.basename(path).len == 0) {
        return error.InvalidConfigPath;
    }

    const bytes = try formatToml(allocator, config);
    defer allocator.free(bytes);

    try dir.writeFile(io, .{ .sub_path = path, .data = bytes });
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

fn writeTomlString(writer: *std.Io.Writer, value: []const u8) SaveError!void {
    if (std.mem.indexOfAny(u8, value, "\"\\\n\r") != null) return error.UnsupportedStringValue;
    try writer.writeByte('"');
    try writer.writeAll(value);
    try writer.writeByte('"');
}

const Section = enum {
    root,
    api,
    display,
    collection,
    interface,
};

fn trimWhitespaceAndComment(line: []const u8) []const u8 {
    const without_cr = std.mem.trim(u8, line, "\r");
    const comment_index = std.mem.indexOfScalar(u8, without_cr, '#') orelse without_cr.len;
    return std.mem.trim(u8, without_cr[0..comment_index], " \t\r");
}

fn parseSection(line: []const u8) ParseError!Section {
    if (line.len < 3 or line[line.len - 1] != ']') return error.InvalidSection;
    const name = std.mem.trim(u8, line[1 .. line.len - 1], " \t\r");
    if (std.mem.eql(u8, name, "api")) return .api;
    if (std.mem.eql(u8, name, "display")) return .display;
    if (std.mem.eql(u8, name, "collection")) return .collection;
    if (std.mem.eql(u8, name, "interface")) return .interface;
    return error.UnknownSection;
}

fn parseApiValue(api: *Api, key: []const u8, value: []const u8) ParseError!void {
    if (std.mem.eql(u8, key, "token")) {
        api.token = try parseString(value);
        return;
    }
    return error.UnknownKey;
}

fn parseDisplayValue(display: *Display, key: []const u8, value: []const u8) ParseError!void {
    if (std.mem.eql(u8, key, "show_images")) {
        display.show_images = try parseBool(value);
    } else if (std.mem.eql(u8, key, "image_protocol")) {
        display.image_protocol = try parseEnum(ImageProtocol, value);
    } else if (std.mem.eql(u8, key, "list_width")) {
        display.list_width = try parseU16(value);
    } else if (std.mem.eql(u8, key, "thread_width")) {
        display.thread_width = try parseU16(value);
    } else if (std.mem.eql(u8, key, "detail_width")) {
        display.detail_width = try parseU16(value);
    } else {
        return error.UnknownKey;
    }
}

fn parseCollectionValue(collection: *Collection, key: []const u8, value: []const u8) ParseError!void {
    if (std.mem.eql(u8, key, "default_username")) {
        collection.default_username = nonEmptyTrimmed(try parseString(value));
    } else if (std.mem.eql(u8, key, "status_filter")) {
        collection.status_filter = try parseEnum(CollectionStatus, value);
    } else {
        return error.UnknownKey;
    }
}

fn parseInterfaceValue(interface: *Interface, key: []const u8, value: []const u8) ParseError!void {
    if (std.mem.eql(u8, key, "color_theme")) {
        interface.color_theme = try parseString(value);
    } else if (std.mem.eql(u8, key, "transition")) {
        interface.transition = try parseString(value);
    } else if (std.mem.eql(u8, key, "selection")) {
        interface.selection = try parseString(value);
    } else if (std.mem.eql(u8, key, "list_density")) {
        interface.list_density = try parseString(value);
    } else if (std.mem.eql(u8, key, "date_format")) {
        interface.date_format = try parseString(value);
    } else if (std.mem.eql(u8, key, "border_style")) {
        interface.border_style = try parseString(value);
    } else {
        return error.UnknownKey;
    }
}

fn parseString(value: []const u8) ParseError![]const u8 {
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') return error.InvalidString;
    const inner = value[1 .. value.len - 1];
    if (std.mem.indexOfScalar(u8, inner, '\\') != null) return error.UnsupportedEscape;
    return inner;
}

fn parseBool(value: []const u8) ParseError!bool {
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBool;
}

fn parseU16(value: []const u8) ParseError!u16 {
    return std.fmt.parseInt(u16, value, 10) catch error.InvalidInteger;
}

fn parseEnum(comptime T: type, value: []const u8) ParseError!T {
    const name = try parseString(value);
    return std.meta.stringToEnum(T, name) orelse error.InvalidEnum;
}

fn nonEmptyTrimmed(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

test "config parses toml values into typed schema" {
    const config = try parseToml(
        \\# bgg-tui config
        \\[api]
        \\token = "token-from-file"
        \\
        \\[display]
        \\show_images = false
        \\image_protocol = "off"
        \\list_width = 50
        \\thread_width = 100
        \\detail_width = 110
        \\
        \\[collection]
        \\default_username = "hiro"
        \\status_filter = "wishlist"
        \\
        \\[interface]
        \\color_theme = "dark"
        \\transition = "slide"
        \\selection = "pulse"
        \\list_density = "compact"
        \\date_format = "yyyy/mm/dd"
        \\border_style = "plain"
    );

    try std.testing.expectEqualStrings("token-from-file", config.apiClientToken().?);
    try std.testing.expect(!config.display.show_images);
    try std.testing.expectEqual(ImageProtocol.off, config.display.image_protocol);
    try std.testing.expectEqual(@as(u16, 50), config.display.list_width);
    try std.testing.expectEqual(@as(u16, 100), config.display.thread_width);
    try std.testing.expectEqual(@as(u16, 110), config.display.detail_width);
    try std.testing.expectEqualStrings("hiro", config.collection.default_username.?);
    try std.testing.expectEqual(CollectionStatus.wishlist, config.collection.status_filter);
    try std.testing.expectEqualStrings("dark", config.interface.color_theme);
    try std.testing.expectEqualStrings("slide", config.interface.transition);
    try std.testing.expectEqualStrings("pulse", config.interface.selection);
    try std.testing.expectEqualStrings("compact", config.interface.list_density);
    try std.testing.expectEqualStrings("yyyy/mm/dd", config.interface.date_format);
    try std.testing.expectEqualStrings("plain", config.interface.border_style);
}

test "config parser preserves defaults for omitted values" {
    const config = try parseToml(
        \\[api]
        \\token = "token-from-file"
    );

    try std.testing.expectEqualStrings("token-from-file", config.apiClientToken().?);
    try std.testing.expect(config.display.show_images);
    try std.testing.expectEqual(ImageProtocol.auto, config.display.image_protocol);
    try std.testing.expectEqual(CollectionStatus.own, config.collection.status_filter);
}

test "config parser rejects unknown keys and escaped strings" {
    try std.testing.expectError(error.UnknownKey, parseToml(
        \\[api]
        \\unexpected = "value"
    ));
    try std.testing.expectError(error.UnknownKey, parseToml(
        \\[interface]
        \\future_flag = true
    ));
    try std.testing.expectError(error.UnsupportedEscape, parseToml(
        \\[api]
        \\token = "token\n"
    ));
}

test "config load falls back to defaults and environment token when file is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(primary_token_env, "token-from-env");

    var loaded = try loadConfigFromDir(std.testing.allocator, std.testing.io, tmp.dir, "missing.toml", &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?[]u8, null), loaded.source_bytes);
    try std.testing.expectEqualStrings("token-from-env", loaded.config.apiClientToken().?);
    try std.testing.expectEqual(ImageProtocol.auto, loaded.config.display.image_protocol);
}

test "config load parses file and lets environment token override file token" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "config.toml",
        .data =
        \\[api]
        \\token = "token-from-file"
        \\
        \\[display]
        \\image_protocol = "off"
        ,
    });

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(primary_token_env, "token-from-env");

    var loaded = try loadConfigFromDir(std.testing.allocator, std.testing.io, tmp.dir, "config.toml", &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expect(loaded.source_bytes != null);
    try std.testing.expectEqualStrings("token-from-env", loaded.config.apiClientToken().?);
    try std.testing.expectEqual(ImageProtocol.off, loaded.config.display.image_protocol);
}

test "config formats and parses default config" {
    const bytes = try formatToml(std.testing.allocator, Config.defaults());
    defer std.testing.allocator.free(bytes);

    const parsed = try parseToml(bytes);

    try std.testing.expectEqual(@as(?[]const u8, null), parsed.apiClientToken());
    try std.testing.expect(parsed.display.show_images);
    try std.testing.expectEqual(ImageProtocol.auto, parsed.display.image_protocol);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.collection.default_username);
    try std.testing.expectEqual(CollectionStatus.own, parsed.collection.status_filter);
}

test "config save creates parent directories and writes toml" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var config = Config.defaults();
    config.api.token = "token-to-save";
    config.display.image_protocol = .off;

    try saveConfigToDir(std.testing.allocator, std.testing.io, tmp.dir, "nested/config.toml", config);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try loadConfigFromDir(std.testing.allocator, std.testing.io, tmp.dir, "nested/config.toml", &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("token-to-save", loaded.config.apiClientToken().?);
    try std.testing.expectEqual(ImageProtocol.off, loaded.config.display.image_protocol);
}

test "config save rejects unsupported string values" {
    var config = Config.defaults();
    config.api.token = "token\nwith-newline";

    try std.testing.expectError(error.UnsupportedStringValue, formatToml(std.testing.allocator, config));
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
