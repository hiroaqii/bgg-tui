const std = @import("std");

const bgg_model = @import("bgg/model.zig");

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
    const labels = try allocator.alloc([]const u8, games.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    for (games, 0..) |game, index| {
        labels[index] = try formatHotGameLabel(allocator, game);
        initialized_count = index + 1;
    }

    return labels;
}

pub fn formatHotGameLabel(allocator: std.mem.Allocator, game: bgg_model.HotGame) ![]u8 {
    if (game.year_published) |year| {
        return try std.fmt.allocPrint(allocator, "#{d: >2}  {s} ({d})", .{ game.rank, game.name, year });
    }
    return try std.fmt.allocPrint(allocator, "#{d: >2}  {s}", .{ game.rank, game.name });
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

    for (items, 0..) |item, index| {
        labels[index] = try formatCollectionItemLabel(allocator, item);
        initialized_count = index + 1;
    }

    return labels;
}

pub fn formatCollectionItemLabel(allocator: std.mem.Allocator, item: bgg_model.CollectionItem) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll(item.name);
    if (item.year_published) |year| try out.writer.print(" ({d})", .{year});

    // Keep the label single-line for the current list component while still
    // surfacing the core collection metadata users need for scanning.
    try out.writer.writeAll("  ");
    try writeCollectionRating(&out.writer, "user", item.rating);
    try out.writer.writeAll("  ");
    try writeCollectionRating(&out.writer, "BGG", item.bgg_rating);
    if (item.rank > 0) try out.writer.print("  rank #{d}", .{item.rank});
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
        try writer.writeByte('-');
    } else {
        try writer.print("{d:.1}", .{rating});
    }
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

    try std.testing.expectEqualStrings("# 1  CATAN (1995)", with_year);
    try std.testing.expectEqualStrings("#12  Unknown Year", without_year);
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

    try std.testing.expectEqualStrings("CATAN (1995)  user 7.0  BGG 6.5  rank #1  plays 3", label);
}
