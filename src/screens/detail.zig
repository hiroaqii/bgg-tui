const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_html = @import("../bgg/html.zig");
const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const format = @import("../format.zig");

pub const LoadState = union(enum) {
    idle,
    loading,
    loaded,
    failed: []const u8,
};

pub const ImageState = union(enum) {
    idle,
    disabled,
    unavailable,
    loading,
    cached: []u8,
    failed: []const u8,
};

pub const State = struct {
    request_id: u64 = 0,
    image_request_id: u64 = 0,
    load_state: LoadState = .idle,
    image_state: ImageState = .idle,
    games: []bgg_model.Game = &.{},
    rendered_text: []u8 = "",
    lines: []const []const u8 = &.{},
    scroll: usize = 0,
    visible_height: usize = 1,
    browser_error_url: []u8 = "",

    pub fn setLoading(self: *State, allocator: std.mem.Allocator) void {
        self.load_state = .loading;
        self.clearImage(allocator);
    }

    pub fn setFailed(self: *State, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    pub fn setLoaded(self: *State, allocator: std.mem.Allocator, games: []bgg_model.Game, detail_width: usize) !void {
        self.deinit(allocator);
        self.games = games;
        try self.rebuildLines(allocator, detail_width);
        self.scroll = 0;
        self.load_state = .loaded;
    }

    pub fn setImageDisabled(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .disabled;
    }

    pub fn setImageUnavailable(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .unavailable;
    }

    pub fn setImageLoading(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .loading;
    }

    pub fn setImageCached(self: *State, allocator: std.mem.Allocator, path: []u8) void {
        self.clearImage(allocator);
        self.image_state = .{ .cached = path };
    }

    pub fn setImageFailed(self: *State, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearImage(allocator);
        self.image_state = .{ .failed = message };
    }

    pub fn imagePath(self: *const State) ?[]const u8 {
        return switch (self.image_state) {
            .cached => |path| path,
            else => null,
        };
    }

    pub fn moveUp(self: *State) void {
        if (self.scroll > 0) self.scroll -= 1;
    }

    pub fn moveDown(self: *State, visible_height: usize) void {
        const max = self.maxScroll(visible_height);
        if (self.scroll < max) self.scroll += 1;
    }

    pub fn setVisibleHeight(self: *State, visible_height: usize) void {
        self.visible_height = @max(visible_height, 1);
        self.scroll = @min(self.scroll, self.maxScroll(self.visible_height));
    }

    pub fn visibleRange(self: *const State, visible_height: usize) ui.Viewport.Range {
        return ui.Viewport.init(.{
            .total = self.lines.len,
            .height = visible_height,
            .offset = self.scroll,
        }).visibleRange();
    }

    pub fn maxScroll(self: *const State, visible_height: usize) usize {
        return ui.Viewport.init(.{
            .total = self.lines.len,
            .height = visible_height,
            .offset = self.scroll,
        }).maxOffset();
    }

    pub fn setBrowserErrorUrl(self: *State, allocator: std.mem.Allocator, url: []const u8) !void {
        self.clearBrowserErrorUrl(allocator);
        self.browser_error_url = try allocator.dupe(u8, url);
    }

    pub fn clearBrowserErrorUrl(self: *State, allocator: std.mem.Allocator) void {
        if (self.browser_error_url.len > 0) allocator.free(self.browser_error_url);
        self.browser_error_url = "";
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        bgg_xml.freeGames(allocator, self.games);
        self.clearImage(allocator);
        allocator.free(self.lines);
        allocator.free(self.rendered_text);
        self.clearBrowserErrorUrl(allocator);
        self.games = &.{};
        self.lines = &.{};
        self.rendered_text = "";
        self.scroll = 0;
        self.visible_height = 1;
        self.load_state = .idle;
    }

    fn clearImage(self: *State, allocator: std.mem.Allocator) void {
        switch (self.image_state) {
            .cached => |path| allocator.free(path),
            else => {},
        }
        self.image_state = .idle;
    }

    fn rebuildLines(self: *State, allocator: std.mem.Allocator, detail_width: usize) !void {
        allocator.free(self.lines);
        allocator.free(self.rendered_text);
        self.lines = &.{};
        self.rendered_text = "";

        if (self.games.len == 0) return;
        self.rendered_text = try buildGameDetailContent(allocator, self.games[0], detail_width);
        self.lines = try splitOwnedLines(allocator, self.rendered_text);
    }
};

fn buildGameDetailContent(allocator: std.mem.Allocator, game: bgg_model.Game, detail_width: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll(game.name);
    try out.writer.writeAll("\n\n");

    try out.writer.writeAll("Year         ");
    if (game.year_published) |year| {
        try out.writer.print("{d}\n", .{year});
    } else {
        try out.writer.writeAll("N/A\n");
    }
    try writeRatingDetailLine(&out.writer, game);
    if (game.bayes_average > 0) {
        try out.writer.writeAll("Geek Rating  ");
        try format.writeFixedDecimal(&out.writer, game.bayes_average, 2);
        try out.writer.writeByte('\n');
    }
    try writeRankDetailLine(&out.writer, game.rank);
    try writePlayersDetailLine(&out.writer, game);
    if (game.player_count_poll) |poll| {
        try writePlayerCountPollTable(&out.writer, poll);
    }
    try writeTimeDetailLine(&out.writer, game);
    try writeWeightDetailLine(&out.writer, game);
    if (game.min_age > 0) try out.writer.print("Age          {d}+\n", .{game.min_age});
    if (game.owned > 0) {
        try out.writer.writeAll("Owned        ");
        try format.writeUnsignedGrouped(&out.writer, game.owned);
        try out.writer.writeByte('\n');
    }
    if (game.num_comments > 0) {
        try out.writer.writeAll("Comments     ");
        try format.writeUnsignedGrouped(&out.writer, game.num_comments);
        try out.writer.writeByte('\n');
    }

    try writeJoinedDetailValues(&out.writer, "Designer", game.designers, detail_width);
    try writeJoinedDetailValues(&out.writer, "Artist", game.artists, detail_width);
    try writeJoinedDetailValues(&out.writer, "Categories", game.categories, detail_width);
    try writeJoinedDetailValues(&out.writer, "Mechanics", game.mechanics, detail_width);

    try out.writer.writeAll("\nDescription\n");
    const description = if (game.description.len == 0) "No description available." else game.description;
    const body = try bgg_html.toText(allocator, description, .{ .wrap_width = detail_width });
    defer allocator.free(body);
    try out.writer.writeAll(body);

    return try out.toOwnedSlice();
}

fn writeRatingDetailLine(writer: *std.Io.Writer, game: bgg_model.Game) !void {
    try writer.writeAll("Rating       ");
    if (game.rating <= 0) {
        try writer.writeAll("N/A\n");
        return;
    }

    try format.writeFixedDecimal(writer, game.rating, 2);
    try writer.writeAll(" (");
    try format.writeUnsignedGrouped(writer, game.users_rated);
    try writer.writeAll(" votes");
    if (game.stddev > 0) {
        try writer.writeAll(", σ ");
        try format.writeFixedDecimal(writer, game.stddev, 2);
    }
    try writer.writeByte(')');
    if (game.median > 0) {
        try writer.writeAll(" median ");
        try format.writeFixedDecimal(writer, game.median, 2);
    }
    try writer.writeByte('\n');
}

fn writeRankDetailLine(writer: *std.Io.Writer, rank: u32) !void {
    try writer.writeAll("Rank         ");
    if (rank == 0) {
        try writer.writeAll("Not Ranked\n");
        return;
    }
    try writer.writeByte('#');
    try format.writeUnsignedGrouped(writer, rank);
    try writer.writeByte('\n');
}

fn writePlayersDetailLine(writer: *std.Io.Writer, game: bgg_model.Game) !void {
    try writer.writeAll("Players      ");
    if (game.min_players == 0 and game.max_players == 0) {
        try writer.writeAll("N/A");
    } else if (game.min_players == game.max_players) {
        try writer.print("{d}", .{game.min_players});
    } else {
        try writer.print("{d}-{d}", .{ game.min_players, game.max_players });
    }
    if (game.player_count_poll) |poll| {
        if (poll.recommended_with) |recommended| {
            if (recommended.len > 0) try writer.print("  ({s})", .{recommended});
        }
    }
    try writer.writeByte('\n');
}

fn writeTimeDetailLine(writer: *std.Io.Writer, game: bgg_model.Game) !void {
    try writer.writeAll("Time         ");
    if (game.playing_time == 0 and game.min_play_time == 0 and game.max_play_time == 0) {
        try writer.writeAll("N/A\n");
    } else if (game.min_play_time > 0 and game.max_play_time > 0 and game.min_play_time != game.max_play_time) {
        try writer.print("{d}-{d} min\n", .{ game.min_play_time, game.max_play_time });
    } else {
        try writer.print("{d} min\n", .{game.playing_time});
    }
}

fn writeWeightDetailLine(writer: *std.Io.Writer, game: bgg_model.Game) !void {
    try writer.writeAll("Weight       ");
    if (game.weight <= 0) {
        try writer.writeAll("N/A\n");
        return;
    }

    try format.writeFixedDecimal(writer, game.weight, 2);
    try writer.print(" / 5 - {s}", .{complexityLabel(game.weight)});
    if (game.num_weights > 0) {
        try writer.writeAll(" (");
        try format.writeUnsignedGrouped(writer, game.num_weights);
        try writer.writeAll(" votes)");
    }
    try writer.writeByte('\n');
}

fn writeJoinedDetailValues(writer: *std.Io.Writer, label: []const u8, values: []const []const u8, detail_width: usize) !void {
    if (values.len == 0) return;

    try writer.writeAll(label);
    try writeSpaces(writer, 12 -| @min(@as(usize, 12), format.displayWidth(label)));
    try writer.writeByte(' ');

    var line_width = @max(@as(usize, 13), format.displayWidth(label) + 1);
    for (values, 0..) |value, index| {
        const prefix = if (index == 0) "" else ", ";
        const part_width = format.displayWidth(prefix) + format.displayWidth(value);
        if (line_width > 13 and line_width + part_width > detail_width) {
            try writer.writeByte('\n');
            try writeSpaces(writer, 13);
            line_width = 13;
        }
        try writer.writeAll(prefix);
        try writer.writeAll(value);
        line_width += part_width;
    }
    try writer.writeByte('\n');
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        try writer.writeByte(' ');
    }
}

fn writePlayerCountPollTable(writer: *std.Io.Writer, poll: bgg_model.PlayerCountPoll) !void {
    if (poll.results.len == 0) return;

    var players_width: usize = 2;
    var best_width: usize = 4;
    var recommended_width: usize = 3;
    var not_recommended_width: usize = 7;
    var valid_rows: usize = 0;
    for (poll.results) |result| {
        const total = result.best + result.recommended + result.not_recommended;
        if (total == 0) continue;
        valid_rows += 1;
        players_width = @max(players_width, format.displayWidth(result.num_players));
        best_width = @max(best_width, pollVoteWidth(result.best, total));
        recommended_width = @max(recommended_width, pollVoteWidth(result.recommended, total));
        not_recommended_width = @max(not_recommended_width, pollVoteWidth(result.not_recommended, total));
    }
    if (valid_rows == 0) return;

    try writePollBorder(writer, "┌", "┬", "┐", players_width, best_width, recommended_width, not_recommended_width);
    try writer.writeAll("  │ ");
    try writeRightAlignedText(writer, "", players_width);
    try writer.writeAll(" │ ");
    try writeRightAlignedText(writer, "Best", best_width);
    try writer.writeAll(" │ ");
    try writeRightAlignedText(writer, "Rec", recommended_width);
    try writer.writeAll(" │ ");
    try writeRightAlignedText(writer, "Not Rec", not_recommended_width);
    try writer.writeAll(" │\n");
    try writePollBorder(writer, "├", "┼", "┤", players_width, best_width, recommended_width, not_recommended_width);
    for (poll.results) |result| {
        const total = result.best + result.recommended + result.not_recommended;
        if (total == 0) continue;
        try writer.writeAll("  │ ");
        try writeRightAlignedText(writer, result.num_players, players_width);
        try writer.writeAll(" │ ");
        try writeRightAlignedPollVote(writer, result.best, total, best_width);
        try writer.writeAll(" │ ");
        try writeRightAlignedPollVote(writer, result.recommended, total, recommended_width);
        try writer.writeAll(" │ ");
        try writeRightAlignedPollVote(writer, result.not_recommended, total, not_recommended_width);
        try writer.writeAll(" │\n");
    }
    try writePollBorder(writer, "└", "┴", "┘", players_width, best_width, recommended_width, not_recommended_width);
}

fn writePollBorder(writer: *std.Io.Writer, left: []const u8, middle: []const u8, right: []const u8, players_width: usize, best_width: usize, recommended_width: usize, not_recommended_width: usize) !void {
    try writer.writeAll("  ");
    try writer.writeAll(left);
    try writeRepeat(writer, "─", players_width + 2);
    try writer.writeAll(middle);
    try writeRepeat(writer, "─", best_width + 2);
    try writer.writeAll(middle);
    try writeRepeat(writer, "─", recommended_width + 2);
    try writer.writeAll(middle);
    try writeRepeat(writer, "─", not_recommended_width + 2);
    try writer.writeAll(right);
    try writer.writeByte('\n');
}

fn writeRightAlignedText(writer: *std.Io.Writer, text: []const u8, width: usize) !void {
    try writeSpaces(writer, width -| @min(width, format.displayWidth(text)));
    try writer.writeAll(text);
}

fn writeRightAlignedPollVote(writer: *std.Io.Writer, value: u32, total: u32, width: usize) !void {
    const actual_width = pollVoteWidth(value, total);
    try writeSpaces(writer, width -| @min(width, actual_width));
    try format.writeUnsignedGrouped(writer, value);
    try writer.print(" ({d}%)", .{pollVotePercent(value, total)});
}

fn pollVoteWidth(value: u32, total: u32) usize {
    return unsignedGroupedWidth(value) + countDigits(pollVotePercent(value, total)) + 4;
}

fn pollVotePercent(value: u32, total: u32) u32 {
    if (total == 0) return 0;
    return @intCast((@as(u64, value) * 100) / @as(u64, total));
}

fn unsignedGroupedWidth(value: u32) usize {
    if (value < 1000) return countDigits(value);
    return countDigits(value) + ((countDigits(value) - 1) / 3);
}

fn countDigits(value: u32) usize {
    var n = value;
    var count: usize = 1;
    while (n >= 10) {
        n /= 10;
        count += 1;
    }
    return count;
}

fn writeRepeat(writer: *std.Io.Writer, text: []const u8, count: usize) !void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        try writer.writeAll(text);
    }
}

fn complexityLabel(weight: f64) []const u8 {
    if (weight < 1.0) return "Light";
    if (weight < 2.0) return "Medium Light";
    if (weight < 3.0) return "Medium";
    if (weight < 4.0) return "Medium Heavy";
    return "Heavy";
}

fn splitOwnedLines(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer lines.deinit(allocator);

    var start: usize = 0;
    var index: usize = 0;
    while (index <= text.len) : (index += 1) {
        if (index == text.len or text[index] == '\n') {
            try lines.append(allocator, text[start..index]);
            start = index + 1;
        }
    }

    return try lines.toOwnedSlice(allocator);
}

pub fn lineStyle(line: []const u8) chasen.TextStyle {
    if (std.mem.eql(u8, line, "Description")) return .{ .dim = true };
    if (std.mem.startsWith(u8, line, "  ┌") or
        std.mem.startsWith(u8, line, "  │") or
        std.mem.startsWith(u8, line, "  ├") or
        std.mem.startsWith(u8, line, "  └"))
    {
        return .{ .dim = true };
    }
    return .{};
}

pub const Layout = struct {
    content_row: u16,
    content_height: usize,
    scroll_row: u16,
    footer_row: u16,
};

pub const LayoutOptions = struct {
    outer_reserved_rows: u16 = 0,
};

pub fn layout(area_height: u16, density: []const u8, options: LayoutOptions) Layout {
    if (area_height == 0) {
        return .{ .content_row = 0, .content_height = 1, .scroll_row = 0, .footer_row = 0 };
    }

    const top = contentTopPadding(area_height, density);
    const max_visible = if (area_height > top + 3) area_height - top - 3 else 1;
    const effective_height = area_height + options.outer_reserved_rows;
    const visible = @max(@as(usize, 1), @min(contentHeight(effective_height, density), @as(usize, max_visible)));
    const visible_u16: u16 = @intCast(@min(visible, std.math.maxInt(u16)));
    const scroll_row = @min(area_height - 1, top + visible_u16);

    return .{
        .content_row = top,
        .content_height = visible,
        .scroll_row = scroll_row,
        .footer_row = @min(area_height - 1, scroll_row + 2),
    };
}

pub fn contentHeight(area_height: u16, density: []const u8) usize {
    return @max(@as(usize, 1), @as(usize, area_height) -| densityOverhead(density));
}

fn contentTopPadding(area_height: u16, density: []const u8) u16 {
    const overhead = densityOverhead(density);
    const preferred = @as(u16, @intCast((overhead -| 2) / 3));
    return @min(preferred, area_height -| 1);
}

fn densityOverhead(density: []const u8) usize {
    if (std.mem.eql(u8, density, "compact")) return 8;
    if (std.mem.eql(u8, density, "relaxed")) return 16;
    return 12;
}

test "game detail state owns loaded game result" {
    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "CATAN"),
        .description = try std.testing.allocator.dupe(u8, "Trade, build, settle."),
    };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games, 90);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 1), state.games.len);
    try std.testing.expectEqualStrings("CATAN", state.games[0].name);
    try std.testing.expect(state.lines.len > 4);
    try std.testing.expectEqualStrings("CATAN", state.lines[0]);
}

test "game detail content follows field order" {
    const designers = [_][]const u8{ "Klaus Teuber", "Someone Else" };
    const categories = [_][]const u8{ "Negotiation", "Economic" };
    const mechanics = [_][]const u8{ "Trading", "Dice Rolling" };
    var poll_results = [_]bgg_model.PlayerCountVotes{
        .{ .num_players = "1", .best = 0, .recommended = 0, .not_recommended = 3 },
        .{ .num_players = "2", .best = 2, .recommended = 1, .not_recommended = 2 },
        .{ .num_players = "5+", .best = 1, .recommended = 0, .not_recommended = 1 },
    };
    const game = bgg_model.Game{
        .id = 13,
        .name = "CATAN",
        .year_published = 1995,
        .description = "Trade <b>resources</b> and build roads.\n\nSettle the island.",
        .min_players = 3,
        .max_players = 4,
        .playing_time = 120,
        .min_age = 10,
        .rating = 7.14,
        .users_rated = 123456,
        .bayes_average = 6.98,
        .rank = 389,
        .weight = 2.32,
        .num_weights = 9876,
        .designers = &designers,
        .categories = &categories,
        .mechanics = &mechanics,
        .player_count_poll = .{
            .recommended_with = "Recommended with 3-4 players",
            .results = &poll_results,
        },
    };

    const text = try buildGameDetailContent(std.testing.allocator, game, 72);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "CATAN\n\nYear         1995") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Rating       7.14 (123,456 votes)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Geek Rating  6.98") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Rank         #389") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Players      3-4  (Recommended with 3-4 players)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  ┌────┬─────────┬─────────┬──────────┐") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  │    │    Best │     Rec │  Not Rec │") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  │ 5+ │ 1 (50%) │  0 (0%) │  1 (50%) │") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  └────┴─────────┴─────────┴──────────┘") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Weight       2.32 / 5 - Medium") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Designer     Klaus Teuber, Someone Else") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\nDescription\nTrade resources and build roads.\n\nSettle the island.") != null);
}

test "detail content height follows density overhead" {
    try std.testing.expectEqual(@as(usize, 22), contentHeight(30, "compact"));
    try std.testing.expectEqual(@as(usize, 18), contentHeight(30, "normal"));
    try std.testing.expectEqual(@as(usize, 14), contentHeight(30, "relaxed"));
    try std.testing.expectEqual(@as(usize, 1), contentHeight(5, "normal"));
}

test "detail layout keeps content and footer positions consistent" {
    const normal = layout(47, "normal", .{});
    try std.testing.expectEqual(@as(u16, 3), normal.content_row);
    try std.testing.expectEqual(@as(usize, 35), normal.content_height);
    try std.testing.expectEqual(@as(u16, 38), normal.scroll_row);
    try std.testing.expectEqual(@as(u16, 40), normal.footer_row);

    const compensated = layout(44, "normal", .{ .outer_reserved_rows = 3 });
    try std.testing.expectEqual(@as(usize, 35), compensated.content_height);

    const small = layout(5, "normal", .{});
    try std.testing.expect(small.content_height >= 1);
    try std.testing.expect(small.footer_row < 5);
}

test "detail line style does not dim wrapped metadata lines" {
    try std.testing.expect(!lineStyle("             Deck Building, Hand Management").dim);
    try std.testing.expect(lineStyle("  │ 5+ │ 1 (50%) │  0 (0%) │  1 (50%) │").dim);
    try std.testing.expect(lineStyle("Description").dim);
}

test "player count poll table skips polls without vote rows" {
    var poll_results = [_]bgg_model.PlayerCountVotes{
        .{ .num_players = "1" },
        .{ .num_players = "2" },
    };
    const poll = bgg_model.PlayerCountPoll{ .results = &poll_results };

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    try writePlayerCountPollTable(&out.writer, poll);
    try std.testing.expectEqualStrings("", out.written());
}
