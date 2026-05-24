const std = @import("std");
const builtin = @import("builtin");

pub const OpenError = error{
    UnsupportedPlatform,
    InvalidUrl,
    UnsupportedUrlScheme,
    UnsupportedUrlHost,
    OpenFailed,
} || std.process.SpawnError || std.process.Child.WaitError;

pub fn openUrl(io: std.Io, url: []const u8) OpenError!void {
    const argv = try commandForUrl(url);
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.OpenFailed,
        else => return error.OpenFailed,
    }
}

pub fn commandForUrl(url: []const u8) OpenError![]const []const u8 {
    try validateOpenUrl(url);
    return switch (builtin.os.tag) {
        .linux => &.{ "xdg-open", url },
        .macos => &.{ "open", url },
        .windows => &.{ "rundll32", "url.dll,FileProtocolHandler", url },
        else => error.UnsupportedPlatform,
    };
}

/// Browser integration only opens app-generated BoardGameGeek HTTPS URLs.
/// The opener is still invoked without a shell, but validating the URL keeps
/// this boundary narrow if a future caller accidentally passes user text.
pub fn validateOpenUrl(url: []const u8) OpenError!void {
    const uri = std.Uri.parse(url) catch return error.InvalidUrl;
    if (!std.mem.eql(u8, uri.scheme, "https")) return error.UnsupportedUrlScheme;

    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = uri.getHost(&host_buffer) catch return error.InvalidUrl;
    if (!std.ascii.eqlIgnoreCase(host.bytes, "boardgamegeek.com")) {
        return error.UnsupportedUrlHost;
    }
}

test "browser command uses platform opener" {
    const argv = commandForUrl("https://boardgamegeek.com/thread/100") catch |err| switch (err) {
        error.UnsupportedPlatform => return,
        else => return err,
    };
    switch (builtin.os.tag) {
        .linux => try std.testing.expectEqualStrings("xdg-open", argv[0]),
        .macos => try std.testing.expectEqualStrings("open", argv[0]),
        .windows => try std.testing.expectEqualStrings("rundll32", argv[0]),
        else => {},
    }
    try std.testing.expectEqualStrings("https://boardgamegeek.com/thread/100", argv[argv.len - 1]);
}

test "browser command rejects non-bgg URLs before opener selection" {
    try std.testing.expectError(error.UnsupportedUrlScheme, commandForUrl("http://boardgamegeek.com/thread/100"));
    try std.testing.expectError(error.UnsupportedUrlHost, commandForUrl("https://example.com/thread/100"));
    try std.testing.expectError(error.InvalidUrl, commandForUrl("not a url"));
}
