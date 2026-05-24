const std = @import("std");
const builtin = @import("builtin");

const config = @import("config.zig");

pub const max_image_bytes = 16 * 1024 * 1024;
pub const cache_dir_name = "images";

pub const CachePathError = std.mem.Allocator.Error || error{
    MissingCacheDirectory,
};

pub const DownloadError = std.mem.Allocator.Error || std.Io.Dir.CreateDirPathError || std.Io.Dir.WriteFileError || error{
    InvalidImageUrl,
    UnsupportedImageScheme,
    ImageRequestFailed,
    ImageTooLarge,
};

pub const CachedImage = struct {
    url: []const u8,
    path: []u8,
};

pub const SourceFormat = enum {
    png,
    jpeg,
    webp,
    unknown,
};

/// Resolves the app image cache directory without creating it.
///
/// The directory follows host cache conventions instead of the config
/// directory so downloaded cover art can be deleted independently from user
/// settings.
pub fn resolveCacheDir(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) CachePathError![]u8 {
    return try resolveCacheDirForOs(allocator, env, builtin.os.tag);
}

pub fn cacheKey(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(url, &digest, .{});
    return try hexDigest(allocator, &digest);
}

pub fn cachePathForUrl(allocator: std.mem.Allocator, cache_dir: []const u8, url: []const u8) ![]u8 {
    const key = try cacheKey(allocator, url);
    defer allocator.free(key);

    const ext = imageExtensionFromUrl(url);
    const file_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ key, ext });
    defer allocator.free(file_name);

    return try std.fs.path.join(allocator, &.{ cache_dir, file_name });
}

pub fn sourceFormatFromUrl(url: []const u8) SourceFormat {
    const ext = imageExtensionFromUrl(url);
    if (std.mem.eql(u8, ext, ".png")) return .png;
    if (std.mem.eql(u8, ext, ".jpg")) return .jpeg;
    if (std.mem.eql(u8, ext, ".webp")) return .webp;
    return .unknown;
}

/// The current Chasen terminal image path can load local PNG files only.
///
/// JPEG/WebP decode is being developed in chasen-graphics. Until that path is
/// connected, bgg-tui should avoid downloading unsupported covers only to fail
/// later in the terminal image loader.
pub fn canLoadTerminalImageFromUrl(url: []const u8) bool {
    return sourceFormatFromUrl(url) == .png;
}

pub fn cacheHit(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

/// Downloads an image URL into the cache and returns the cached path.
///
/// This helper intentionally does not decode or resize. Terminal image
/// loading is a separate Chasen runtime effect; this step only gives the app a
/// stable local file path to hand to that effect.
pub fn downloadToCache(
    allocator: std.mem.Allocator,
    io: std.Io,
    cache_dir: []const u8,
    url: []const u8,
) DownloadError!CachedImage {
    const path = try cachePathForUrl(allocator, cache_dir, url);
    errdefer allocator.free(path);

    if (cacheHit(io, path)) {
        return .{ .url = url, .path = path };
    }

    const body = try downloadImage(allocator, io, url);
    defer allocator.free(body);

    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(io, parent);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = body });

    return .{ .url = url, .path = path };
}

fn downloadImage(allocator: std.mem.Allocator, io: std.Io, url: []const u8) DownloadError![]u8 {
    const uri = std.Uri.parse(url) catch return error.InvalidImageUrl;
    if (!std.mem.eql(u8, uri.scheme, "https") and !std.mem.eql(u8, uri.scheme, "http")) {
        return error.UnsupportedImageScheme;
    }

    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var request = client.request(.GET, uri, .{}) catch return error.ImageRequestFailed;
    defer request.deinit();

    request.sendBodiless() catch return error.ImageRequestFailed;

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = request.receiveHead(&redirect_buffer) catch return error.ImageRequestFailed;
    if (response.head.status != .ok) return error.ImageRequestFailed;

    var transfer_buffer: [8 * 1024]u8 = undefined;
    return response.reader(&transfer_buffer).allocRemaining(allocator, .limited(max_image_bytes)) catch |err| switch (err) {
        error.StreamTooLong => error.ImageTooLarge,
        error.OutOfMemory => error.OutOfMemory,
        else => error.ImageRequestFailed,
    };
}

fn resolveCacheDirForOs(
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    os_tag: std.Target.Os.Tag,
) CachePathError![]u8 {
    return switch (os_tag) {
        .windows => {
            if (env.get("LOCALAPPDATA")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinCacheDir(allocator, dir);
            }
            if (env.get("APPDATA")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinCacheDir(allocator, dir);
            }
            return error.MissingCacheDirectory;
        },
        .macos => {
            const home = nonEmptyTrimmed(env.get("HOME")) orelse return error.MissingCacheDirectory;
            const cache_root = try std.fs.path.join(allocator, &.{ home, "Library", "Caches" });
            defer allocator.free(cache_root);
            return try joinCacheDir(allocator, cache_root);
        },
        else => {
            if (env.get("XDG_CACHE_HOME")) |value| {
                if (nonEmptyTrimmed(value)) |dir| return try joinCacheDir(allocator, dir);
            }
            const home = nonEmptyTrimmed(env.get("HOME")) orelse return error.MissingCacheDirectory;
            const cache_root = try std.fs.path.join(allocator, &.{ home, ".cache" });
            defer allocator.free(cache_root);
            return try joinCacheDir(allocator, cache_root);
        },
    };
}

fn joinCacheDir(allocator: std.mem.Allocator, cache_root: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ cache_root, config.app_dir_name, cache_dir_name });
}

fn imageExtensionFromUrl(url: []const u8) []const u8 {
    const path_end = std.mem.indexOfAny(u8, url, "?#") orelse url.len;
    const path = url[0..path_end];
    if (endsWithIgnoreCase(path, ".png")) return ".png";
    if (endsWithIgnoreCase(path, ".jpg")) return ".jpg";
    if (endsWithIgnoreCase(path, ".jpeg")) return ".jpg";
    if (endsWithIgnoreCase(path, ".webp")) return ".webp";
    return ".img";
}

fn endsWithIgnoreCase(text: []const u8, suffix: []const u8) bool {
    if (text.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(text[text.len - suffix.len ..], suffix);
}

fn nonEmptyTrimmed(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

fn hexDigest(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const alphabet = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return out;
}

test "cache dir uses XDG cache home on unix-like systems" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("XDG_CACHE_HOME", "/tmp/cache");
    try env.put("HOME", "/tmp/home");

    const path = try resolveCacheDirForOs(std.testing.allocator, &env, .linux);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/tmp/cache/bgg-tui/images", path);
}

test "cache dir falls back to home cache on unix-like systems" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/tmp/home");

    const path = try resolveCacheDirForOs(std.testing.allocator, &env, .linux);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/tmp/home/.cache/bgg-tui/images", path);
}

test "cache key is stable sha256 hex" {
    const key = try cacheKey(std.testing.allocator, "https://example.com/image.png");
    defer std.testing.allocator.free(key);
    const same_key = try cacheKey(std.testing.allocator, "https://example.com/image.png");
    defer std.testing.allocator.free(same_key);

    try std.testing.expectEqual(@as(usize, 64), key.len);
    try std.testing.expectEqualStrings(key, same_key);
}

test "cache path uses url extension before query string" {
    const path = try cachePathForUrl(std.testing.allocator, "/tmp/cache", "https://example.com/cover.JPG?size=large");
    defer std.testing.allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, ".jpg"));
    try std.testing.expect(std.mem.startsWith(u8, path, "/tmp/cache/"));
}

test "source format is detected from url extension" {
    try std.testing.expectEqual(SourceFormat.png, sourceFormatFromUrl("https://example.com/cover.PNG"));
    try std.testing.expectEqual(SourceFormat.jpeg, sourceFormatFromUrl("https://example.com/cover.jpeg?size=large"));
    try std.testing.expectEqual(SourceFormat.webp, sourceFormatFromUrl("https://example.com/cover.webp"));
    try std.testing.expectEqual(SourceFormat.unknown, sourceFormatFromUrl("https://example.com/cover"));
}

test "terminal image load is limited to PNG until decode pipeline expands" {
    try std.testing.expect(canLoadTerminalImageFromUrl("https://example.com/cover.png"));
    try std.testing.expect(!canLoadTerminalImageFromUrl("https://example.com/cover.jpg"));
    try std.testing.expect(!canLoadTerminalImageFromUrl("https://example.com/cover.webp"));
}
