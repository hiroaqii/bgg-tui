const std = @import("std");

pub const GameSearchResult = struct {
    id: u32,
    name: []const u8,
    year_published: ?i32 = null,
};

pub const HotGame = struct {
    id: u32,
    rank: u32,
    name: []const u8,
    thumbnail_url: ?[]const u8 = null,
    year_published: ?i32 = null,
};

pub const CollectionItem = struct {
    id: u32,
    name: []const u8,
    year_published: ?i32 = null,
    image_url: ?[]const u8 = null,
    thumbnail_url: ?[]const u8 = null,
};

test "model declarations compile" {
    const result = GameSearchResult{ .id = 1, .name = "Gloomhaven" };
    try std.testing.expectEqual(@as(u32, 1), result.id);
}
