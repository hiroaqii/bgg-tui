const std = @import("std");
const builtin = @import("builtin");

pub const OpenError = error{
    UnsupportedPlatform,
} || std.process.SpawnError || std.process.Child.WaitError;

pub fn openUrl(io: std.Io, url: []const u8) OpenError!void {
    const argv = commandForUrl(url) orelse return error.UnsupportedPlatform;
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    _ = try child.wait(io);
}

pub fn commandForUrl(url: []const u8) ?[]const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{ "xdg-open", url },
        .macos => &.{ "open", url },
        .windows => &.{ "rundll32", "url.dll,FileProtocolHandler", url },
        else => null,
    };
}

test "browser command uses platform opener" {
    const argv = commandForUrl("https://boardgamegeek.com/thread/100") orelse return;
    switch (builtin.os.tag) {
        .linux => try std.testing.expectEqualStrings("xdg-open", argv[0]),
        .macos => try std.testing.expectEqualStrings("open", argv[0]),
        .windows => try std.testing.expectEqualStrings("rundll32", argv[0]),
        else => {},
    }
    try std.testing.expectEqualStrings("https://boardgamegeek.com/thread/100", argv[argv.len - 1]);
}
