const std = @import("std");

const Allocator = std.mem.Allocator;

pub const base_url = "https://boardgamegeek.com/xmlapi2";
pub const collection_max_retries = 10;
pub const max_thing_ids = 20;

pub const BuildError = error{
    EmptySearchQuery,
    SearchQueryTooShort,
    EmptyUsername,
    EmptyThingIds,
    TooManyThingIds,
};

pub const CollectionOptions = struct {
    own: bool = false,
    prev_owned: bool = false,
    for_trade: bool = false,
    want: bool = false,
    want_to_play: bool = false,
    want_to_buy: bool = false,
    wishlist: bool = false,
    preordered: bool = false,
};

pub fn search(allocator: Allocator, query: []const u8) ![]u8 {
    if (query.len == 0) return BuildError.EmptySearchQuery;
    if (query.len < 3) return BuildError.SearchQueryTooShort;

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("/search?query=");
    try writeQueryValue(&out.writer, query);
    try out.writer.writeAll("&type=boardgame,boardgameexpansion");
    return try out.toOwnedSlice();
}

pub fn hot(allocator: Allocator) ![]u8 {
    return try allocator.dupe(u8, "/hot?type=boardgame");
}

pub fn thing(allocator: Allocator, ids: []const u32) ![]u8 {
    if (ids.len == 0) return BuildError.EmptyThingIds;
    if (ids.len > max_thing_ids) return BuildError.TooManyThingIds;

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("/thing?id=");
    for (ids, 0..) |id, index| {
        if (index > 0) try out.writer.writeByte(',');
        try out.writer.print("{d}", .{id});
    }
    try out.writer.writeAll("&stats=1");
    return try out.toOwnedSlice();
}

pub fn collection(allocator: Allocator, username: []const u8, options: CollectionOptions) ![]u8 {
    if (username.len == 0) return BuildError.EmptyUsername;

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("/collection?username=");
    try writeQueryValue(&out.writer, username);
    try out.writer.writeAll("&stats=1");
    try appendFlag(&out.writer, "own", options.own);
    try appendFlag(&out.writer, "prevowned", options.prev_owned);
    try appendFlag(&out.writer, "fortrade", options.for_trade);
    try appendFlag(&out.writer, "want", options.want);
    try appendFlag(&out.writer, "wanttoplay", options.want_to_play);
    try appendFlag(&out.writer, "wanttobuy", options.want_to_buy);
    try appendFlag(&out.writer, "wishlist", options.wishlist);
    try appendFlag(&out.writer, "preordered", options.preordered);
    return try out.toOwnedSlice();
}

pub fn forumList(allocator: Allocator, game_id: u32) ![]u8 {
    return try std.fmt.allocPrint(allocator, "/forumlist?type=thing&id={d}", .{game_id});
}

pub fn forum(allocator: Allocator, forum_id: u32, page: u32) ![]u8 {
    return try std.fmt.allocPrint(allocator, "/forum?id={d}&page={d}", .{ forum_id, if (page == 0) 1 else page });
}

pub fn thread(allocator: Allocator, thread_id: u32) ![]u8 {
    return try std.fmt.allocPrint(allocator, "/thread?id={d}", .{thread_id});
}

fn appendFlag(writer: *std.Io.Writer, name: []const u8, enabled: bool) !void {
    if (!enabled) return;
    try writer.print("&{s}=1", .{name});
}

fn writeQueryValue(writer: *std.Io.Writer, value: []const u8) !void {
    try std.Uri.Component.percentEncode(writer, value, isQueryValueChar);
}

fn isQueryValueChar(char: u8) bool {
    return switch (char) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

test "search endpoint escapes query values" {
    const path = try search(std.testing.allocator, "Catan Cities & Knights");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/search?query=Catan%20Cities%20%26%20Knights&type=boardgame,boardgameexpansion", path);
}

test "thing endpoint supports multiple ids" {
    const path = try thing(std.testing.allocator, &.{ 13, 278 });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/thing?id=13,278&stats=1", path);
}

test "collection endpoint appends enabled filters" {
    const path = try collection(std.testing.allocator, "test user", .{
        .own = true,
        .want_to_play = true,
        .wishlist = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/collection?username=test%20user&stats=1&own=1&wanttoplay=1&wishlist=1", path);
}

test "forum endpoints match BGG XML API paths" {
    const forum_list = try forumList(std.testing.allocator, 13);
    defer std.testing.allocator.free(forum_list);
    try std.testing.expectEqualStrings("/forumlist?type=thing&id=13", forum_list);

    const forum_page = try forum(std.testing.allocator, 21, 0);
    defer std.testing.allocator.free(forum_page);
    try std.testing.expectEqualStrings("/forum?id=21&page=1", forum_page);

    const thread_page = try thread(std.testing.allocator, 1001);
    defer std.testing.allocator.free(thread_page);
    try std.testing.expectEqualStrings("/thread?id=1001", thread_page);
}
