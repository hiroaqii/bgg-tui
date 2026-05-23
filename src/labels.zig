const std = @import("std");

const bgg_model = @import("bgg/model.zig");
const format = @import("format.zig");

const list_name_max_width: usize = 45;

pub fn buildSearchResultLabels(allocator: std.mem.Allocator, results: []const bgg_model.GameSearchResult) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, results.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    for (results, 0..) |result, index| {
        labels[index] = try formatSearchResultLabel(allocator, result);
        initialized_count = index + 1;
    }

    return labels;
}

pub fn formatSearchResultLabel(allocator: std.mem.Allocator, result: bgg_model.GameSearchResult) ![]u8 {
    if (result.year_published) |year| {
        return try std.fmt.allocPrint(allocator, "{s} ({d})", .{ result.name, year });
    }
    return try allocator.dupe(u8, result.name);
}

pub fn freeSearchResultLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

pub fn buildHotGameLabels(allocator: std.mem.Allocator, games: []const bgg_model.HotGame) ![]const []const u8 {
    return buildHotGameLabelsWithStats(allocator, games, &.{});
}

pub fn buildHotGameLabelsWithStats(
    allocator: std.mem.Allocator,
    games: []const bgg_model.HotGame,
    stats: []const bgg_model.Game,
) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, games.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    const name_width = cappedHotGameNameWidth(games);
    for (games, 0..) |game, index| {
        labels[index] = try formatHotGameLabelAligned(allocator, game, hotStatsFor(stats, game.id), name_width);
        initialized_count = index + 1;
    }

    return labels;
}

pub fn formatHotGameLabel(allocator: std.mem.Allocator, game: bgg_model.HotGame) ![]u8 {
    return formatHotGameLabelAligned(allocator, game, null, cappedNameWidth(hotGameNameWidth(game)));
}

fn formatHotGameLabelAligned(
    allocator: std.mem.Allocator,
    game: bgg_model.HotGame,
    stats: ?bgg_model.Game,
    name_width: usize,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.print("#{d}", .{game.rank});
    try writePadding(&out.writer, hotRankPadding(game.rank));
    try writeHotGameName(allocator, &out.writer, game, name_width);

    if (stats) |game_stats| {
        try writePadding(&out.writer, name_width - cappedNameWidth(hotGameNameWidth(game)) + 2);
        try writeGameRating(&out.writer, "★", game_stats.rating);
        try out.writer.writeAll("  ");
        try writeGameRating(&out.writer, "⚖", game_stats.weight);
        try out.writer.writeAll("  ");
        try writeGameRank(&out.writer, game_stats.rank);
    }

    return try out.toOwnedSlice();
}

pub fn freeHotGameLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

pub fn buildCollectionItemLabels(allocator: std.mem.Allocator, items: []const bgg_model.CollectionItem) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, items.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    const name_width = cappedCollectionNameWidth(items);
    for (items, 0..) |item, index| {
        labels[index] = try formatCollectionItemLabelAligned(allocator, item, name_width);
        initialized_count = index + 1;
    }

    return labels;
}

pub fn formatCollectionItemLabel(allocator: std.mem.Allocator, item: bgg_model.CollectionItem) ![]u8 {
    return formatCollectionItemLabelAligned(allocator, item, cappedNameWidth(collectionNameWidth(item)));
}

fn formatCollectionItemLabelAligned(allocator: std.mem.Allocator, item: bgg_model.CollectionItem, name_width: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try writeCollectionName(allocator, &out.writer, item, name_width);

    // Keep stats in fixed columns so the list can be scanned like the Go UI.
    try writePadding(&out.writer, name_width - cappedNameWidth(collectionNameWidth(item)) + 2);
    try writeCollectionRating(&out.writer, "♥", item.rating);
    try out.writer.writeAll("  ");
    try writeCollectionRating(&out.writer, "★", item.bgg_rating);
    try out.writer.writeAll("  ");
    try writeCollectionRank(&out.writer, item.rank);
    if (item.num_plays > 0) try out.writer.print("  plays {d}", .{item.num_plays});

    return try out.toOwnedSlice();
}

pub fn freeCollectionItemLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

fn writeCollectionRating(writer: *std.Io.Writer, label: []const u8, rating: f64) !void {
    try writer.print("{s} ", .{label});
    if (rating <= 0) {
        try writer.writeAll("    -");
    } else {
        try writer.print("{d: >5.2}", .{rating});
    }
}

fn writeCollectionRank(writer: *std.Io.Writer, rank: u32) !void {
    if (rank == 0) {
        try writer.writeAll("    -");
    } else {
        try writer.print("#{d}", .{rank});
    }
}

fn writeGameRating(writer: *std.Io.Writer, label: []const u8, rating: f64) !void {
    try writer.print("{s} ", .{label});
    if (rating <= 0) {
        try writer.writeAll("    -");
    } else {
        try writer.print("{d: >5.2}", .{rating});
    }
}

fn writeGameRank(writer: *std.Io.Writer, rank: u32) !void {
    if (rank == 0) {
        try writer.writeAll("    -");
    } else {
        try writer.print("#{d}", .{rank});
    }
}

fn writeHotGameName(allocator: std.mem.Allocator, writer: *std.Io.Writer, game: bgg_model.HotGame, max_width: usize) !void {
    var name: std.Io.Writer.Allocating = .init(allocator);
    defer name.deinit();
    try name.writer.writeAll(game.name);
    if (game.year_published) |year| try name.writer.print(" ({d})", .{year});
    try format.writeTruncated(writer, name.written(), max_width, "…");
}

fn writeCollectionName(allocator: std.mem.Allocator, writer: *std.Io.Writer, item: bgg_model.CollectionItem, max_width: usize) !void {
    var name: std.Io.Writer.Allocating = .init(allocator);
    defer name.deinit();
    try name.writer.writeAll(item.name);
    if (item.year_published) |year| try name.writer.print(" ({d})", .{year});
    try format.writeTruncated(writer, name.written(), max_width, "…");
}

fn hotGameNameWidth(game: bgg_model.HotGame) usize {
    var width = format.displayWidth(game.name);
    if (game.year_published) |year| {
        var buf: [16]u8 = undefined;
        const year_text = std.fmt.bufPrint(&buf, " ({d})", .{year}) catch return width;
        width += format.displayWidth(year_text);
    }
    return width;
}

fn cappedHotGameNameWidth(games: []const bgg_model.HotGame) usize {
    var max_width: usize = 0;
    for (games) |game| max_width = @max(max_width, hotGameNameWidth(game));
    return cappedNameWidth(max_width);
}

fn hotStatsFor(stats: []const bgg_model.Game, id: u32) ?bgg_model.Game {
    for (stats) |game| {
        if (game.id == id) return game;
    }
    return null;
}

fn hotRankPadding(rank: u32) usize {
    if (rank < 10) return 3;
    if (rank < 100) return 2;
    return 1;
}

fn collectionNameWidth(item: bgg_model.CollectionItem) usize {
    var width = format.displayWidth(item.name);
    if (item.year_published) |year| {
        var buf: [16]u8 = undefined;
        const year_text = std.fmt.bufPrint(&buf, " ({d})", .{year}) catch return width;
        width += format.displayWidth(year_text);
    }
    return width;
}

fn cappedCollectionNameWidth(items: []const bgg_model.CollectionItem) usize {
    var max_width: usize = 0;
    for (items) |item| max_width = @max(max_width, collectionNameWidth(item));
    return cappedNameWidth(max_width);
}

fn cappedNameWidth(width: usize) usize {
    return @min(width, list_name_max_width);
}

fn writePadding(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

test "hot game labels include rank and optional year" {
    const with_year = try formatHotGameLabel(std.testing.allocator, .{
        .id = 13,
        .rank = 1,
        .name = "CATAN",
        .year_published = 1995,
    });
    defer std.testing.allocator.free(with_year);

    const without_year = try formatHotGameLabel(std.testing.allocator, .{
        .id = 42,
        .rank = 12,
        .name = "Unknown Year",
    });
    defer std.testing.allocator.free(without_year);

    try std.testing.expectEqualStrings("#1   CATAN (1995)", with_year);
    try std.testing.expectEqualStrings("#12  Unknown Year", without_year);
}

test "hot game labels append aligned stats when available" {
    const games = [_]bgg_model.HotGame{
        .{ .id = 1, .rank = 1, .name = "Short" },
        .{ .id = 2, .rank = 12, .name = "Longer Game", .year_published = 2024 },
    };
    const stats = [_]bgg_model.Game{
        .{ .id = 1, .name = "Short", .rating = 7.25, .weight = 2.5, .rank = 42 },
        .{ .id = 2, .name = "Longer Game", .rating = 8, .weight = 3.75 },
    };

    const built = try buildHotGameLabelsWithStats(std.testing.allocator, &games, &stats);
    defer freeHotGameLabels(std.testing.allocator, built);

    try std.testing.expectEqualStrings("#1   Short               ★  7.25  ⚖  2.50  #42", built[0]);
    try std.testing.expectEqualStrings("#12  Longer Game (2024)  ★  8.00  ⚖  3.75      -", built[1]);
}

test "hot game labels truncate long names before stats columns" {
    const games = [_]bgg_model.HotGame{
        .{ .id = 1, .rank = 1, .name = "The Extremely Long Board Game Name That Would Push Stats Away" },
    };
    const stats = [_]bgg_model.Game{
        .{ .id = 1, .name = "The Extremely Long Board Game Name That Would Push Stats Away", .rating = 6.65, .weight = 2.75, .rank = 100 },
    };

    const built = try buildHotGameLabelsWithStats(std.testing.allocator, &games, &stats);
    defer freeHotGameLabels(std.testing.allocator, built);

    try std.testing.expectEqualStrings("#1   The Extremely Long Board Game Name That Woul…  ★  6.65  ⚖  2.75  #100", built[0]);
}

test "search result labels include optional year" {
    const with_year = try formatSearchResultLabel(std.testing.allocator, .{
        .id = 13,
        .name = "CATAN",
        .year_published = 1995,
    });
    defer std.testing.allocator.free(with_year);

    const without_year = try formatSearchResultLabel(std.testing.allocator, .{
        .id = 42,
        .name = "No Year",
    });
    defer std.testing.allocator.free(without_year);

    try std.testing.expectEqualStrings("CATAN (1995)", with_year);
    try std.testing.expectEqualStrings("No Year", without_year);
}

test "collection item labels omit status marker for Go compatibility" {
    const label = try formatCollectionItemLabel(std.testing.allocator, .{
        .id = 13,
        .name = "CATAN",
        .year_published = 1995,
        .num_plays = 3,
        .rating = 7.0,
        .bgg_rating = 6.5,
        .rank = 1,
        .owned = true,
    });
    defer std.testing.allocator.free(label);

    try std.testing.expectEqualStrings("CATAN (1995)  ♥  7.00  ★  6.50  #1  plays 3", label);
}

test "collection item labels align stat columns" {
    const items = [_]bgg_model.CollectionItem{
        .{ .id = 1, .name = "Short", .rating = 7, .bgg_rating = 6.5, .rank = 1 },
        .{ .id = 2, .name = "Longer Game", .year_published = 2024, .rating = 0, .bgg_rating = 8.25 },
    };
    const built = try buildCollectionItemLabels(std.testing.allocator, &items);
    defer freeCollectionItemLabels(std.testing.allocator, built);

    try std.testing.expectEqualStrings("Short               ♥  7.00  ★  6.50  #1", built[0]);
    try std.testing.expectEqualStrings("Longer Game (2024)  ♥     -  ★  8.25      -", built[1]);
}

test "collection item labels truncate long names before stats columns" {
    const items = [_]bgg_model.CollectionItem{
        .{ .id = 1, .name = "The Extremely Long Collection Game Name That Would Push Stats Away", .rating = 7.5, .bgg_rating = 6.65, .rank = 321 },
    };
    const built = try buildCollectionItemLabels(std.testing.allocator, &items);
    defer freeCollectionItemLabels(std.testing.allocator, built);

    try std.testing.expectEqualStrings("The Extremely Long Collection Game Name That…  ♥  7.50  ★  6.65  #321", built[0]);
}
