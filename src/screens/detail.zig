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
    terminal_image_request_id: ?chasen.TerminalImageRequestId = null,
    terminal_image_handle: ?chasen.TerminalImageHandle = null,
    terminal_image_load_error: ?chasen.TerminalImageLoadError = null,
    games: []bgg_model.Game = &.{},
    rendered_text: []u8 = "",
    lines: []const []const u8 = &.{},
    blocks: []const Block = &.{},
    viewport_blocks: []const ui.BlockViewport.Block = &.{},
    viewport: ui.BlockViewport.State = .{},
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
        self.viewport.offset = 0;
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

    pub fn setTerminalImageLoading(self: *State) void {
        self.terminal_image_request_id = null;
        self.terminal_image_handle = null;
        self.terminal_image_load_error = null;
    }

    pub fn setTerminalImageLoaded(self: *State, handle: chasen.TerminalImageHandle) void {
        self.terminal_image_handle = handle;
        self.terminal_image_load_error = null;
    }

    pub fn setTerminalImageFailed(self: *State, reason: chasen.TerminalImageLoadError) void {
        self.terminal_image_handle = null;
        self.terminal_image_load_error = reason;
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
        self.viewport.scrollBy(self.viewport_blocks, self.visible_height, -1);
    }

    pub fn moveDown(self: *State, visible_height: usize) void {
        self.viewport.scrollBy(self.viewport_blocks, visible_height, 1);
    }

    pub fn setVisibleHeight(self: *State, visible_height: usize) void {
        self.visible_height = @max(visible_height, 1);
        self.viewport.clamp(self.viewport_blocks, self.visible_height);
    }

    pub fn rewrap(self: *State, allocator: std.mem.Allocator, detail_width: usize) !void {
        if (self.load_state != .loaded or self.games.len == 0) return;
        try self.rebuildLines(allocator, detail_width);
        self.viewport.clamp(self.viewport_blocks, self.visible_height);
    }

    pub fn maxScroll(self: *const State, visible_height: usize) usize {
        return ui.BlockViewport.maxOffset(self.viewport_blocks, visible_height);
    }

    pub fn scrollOffset(self: *const State) usize {
        return self.viewport.offset;
    }

    pub fn visibleBlocks(self: *const State, visible_height: usize) ui.BlockViewport.Iterator {
        return self.viewport.iterator(self.viewport_blocks, visible_height);
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
        allocator.free(self.blocks);
        allocator.free(self.viewport_blocks);
        allocator.free(self.rendered_text);
        self.clearBrowserErrorUrl(allocator);
        self.games = &.{};
        self.lines = &.{};
        self.blocks = &.{};
        self.viewport_blocks = &.{};
        self.rendered_text = "";
        self.viewport = .{};
        self.visible_height = 1;
        self.load_state = .idle;
    }

    fn clearImage(self: *State, allocator: std.mem.Allocator) void {
        switch (self.image_state) {
            .cached => |path| allocator.free(path),
            else => {},
        }
        self.image_state = .idle;
        self.terminal_image_handle = null;
        self.terminal_image_load_error = null;
        self.terminal_image_request_id = null;
    }

    fn rebuildLines(self: *State, allocator: std.mem.Allocator, detail_width: usize) !void {
        allocator.free(self.lines);
        allocator.free(self.blocks);
        allocator.free(self.viewport_blocks);
        allocator.free(self.rendered_text);
        self.lines = &.{};
        self.blocks = &.{};
        self.viewport_blocks = &.{};
        self.rendered_text = "";

        if (self.games.len == 0) return;
        self.rendered_text = try buildGameDetailContent(allocator, self.games[0], detail_width);
        self.lines = try splitOwnedLines(allocator, self.rendered_text);
        self.blocks = try buildBlocksForGame(allocator, self.lines, self.games[0]);
        self.viewport_blocks = try buildViewportBlocks(allocator, self.blocks);
    }
};

pub const Block = struct {
    kind: Kind,
    line_start: usize,
    line_count: usize,

    pub const Kind = enum {
        title,
        metadata,
        description,
        player_poll_table,
    };

    pub fn height(self: Block) usize {
        return switch (self.kind) {
            .title,
            .metadata,
            .description,
            => self.line_count,
            .player_poll_table => self.line_count,
        };
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

const PlayerPollTableData = struct {
    table: ui.Table,
    rows: []ui.Table.Row,
};

fn playerPollTableData(allocator: std.mem.Allocator, poll: bgg_model.PlayerCountPoll, marker_style: chasen.TextStyle) !PlayerPollTableData {
    var players_width: usize = 2;
    var best_width: usize = 4;
    var recommended_width: usize = 3;
    var not_recommended_width: usize = 7;
    var marker_width: usize = 0;
    var valid_rows: usize = 0;
    for (poll.results) |result| {
        const total = pollVoteTotal(result);
        if (total == 0) continue;
        valid_rows += 1;
        players_width = @max(players_width, format.displayWidth(result.num_players));
        best_width = @max(best_width, pollVoteWidth(result.best, total));
        recommended_width = @max(recommended_width, pollVoteWidth(result.recommended, total));
        not_recommended_width = @max(not_recommended_width, pollVoteWidth(result.not_recommended, total));
        marker_width = @max(marker_width, format.displayWidth(pollRecommendationMarker(result)));
    }

    const columns = try allocator.alloc(ui.Table.Column, 5);
    columns[0] = .{ .header = "", .width = clampU16(players_width + 2), .alignment = .right };
    columns[1] = .{ .header = "Best", .width = clampU16(best_width + 2), .alignment = .right };
    columns[2] = .{ .header = "Rec", .width = clampU16(recommended_width + 2), .alignment = .right };
    columns[3] = .{ .header = "Not Rec", .width = clampU16(not_recommended_width + 2), .alignment = .right };
    columns[4] = .{ .header = "", .width = clampU16(marker_width + 2), .alignment = .left, .cell_style = marker_style };

    const rows = try allocator.alloc(ui.Table.Row, valid_rows);

    var row_index: usize = 0;
    for (poll.results) |result| {
        const total = pollVoteTotal(result);
        if (total == 0) continue;

        const cells = try allocator.alloc([]const u8, 5);
        cells[0] = result.num_players;
        cells[1] = try pollVoteText(allocator, result.best, total);
        cells[2] = try pollVoteText(allocator, result.recommended, total);
        cells[3] = try pollVoteText(allocator, result.not_recommended, total);
        cells[4] = pollRecommendationMarker(result);

        rows[row_index] = cells;
        row_index += 1;
    }

    return .{
        .table = ui.Table.init(.{ .columns = columns, .rows = rows }),
        .rows = rows,
    };
}

fn playerPollTableRenderedRowCount(poll: bgg_model.PlayerCountPoll) usize {
    var valid_rows: usize = 0;
    for (poll.results) |result| {
        if (pollVoteTotal(result) > 0) valid_rows += 1;
    }
    if (valid_rows == 0) return 0;

    const table = ui.Table.init(.{
        .columns = &.{.{ .header = "", .width = 1 }},
        .rows = &.{},
    });
    const chrome_rows = table.renderedRowCountForOptions(.{
        .grid = .full,
        .show_separator = true,
        .body_separators = false,
    });
    return chrome_rows + valid_rows;
}

fn pollVoteText(allocator: std.mem.Allocator, value: u32, total: u32) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    try format.writeUnsignedGrouped(&out.writer, value);
    try out.writer.print(" ({d}%)", .{pollVotePercent(value, total)});
    return try out.toOwnedSlice();
}

fn pollRecommendationMarker(result: bgg_model.PlayerCountVotes) []const u8 {
    if (result.best > result.recommended and result.best > result.not_recommended) return "★ Best";
    if (result.recommended > result.best and result.recommended > result.not_recommended) return "★";
    return "";
}

fn pollVoteTotal(result: bgg_model.PlayerCountVotes) u32 {
    return result.best + result.recommended + result.not_recommended;
}

fn pollVoteWidth(value: u32, total: u32) usize {
    return unsignedGroupedWidth(value) + countDigits(pollVotePercent(value, total)) + 4;
}

fn pollVotePercent(value: u32, total: u32) u32 {
    if (total == 0) return 0;
    return @intCast((@as(u64, value) * 100) / @as(u64, total));
}

fn clampU16(value: usize) u16 {
    return @intCast(@min(value, std.math.maxInt(u16)));
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

pub fn buildBlocks(allocator: std.mem.Allocator, lines: []const []const u8) ![]const Block {
    return buildBlocksForGameOrNull(allocator, lines, null);
}

pub fn buildBlocksForGame(allocator: std.mem.Allocator, lines: []const []const u8, game: bgg_model.Game) ![]const Block {
    return buildBlocksForGameOrNull(allocator, lines, game);
}

fn buildBlocksForGameOrNull(allocator: std.mem.Allocator, lines: []const []const u8, maybe_game: ?bgg_model.Game) ![]const Block {
    var blocks: std.ArrayList(Block) = .empty;
    errdefer blocks.deinit(allocator);

    const poll_height = if (maybe_game) |game|
        if (game.player_count_poll) |poll| playerPollTableRenderedRowCount(poll) else 0
    else
        0;
    var poll_inserted = false;

    var index: usize = 0;
    while (index < lines.len) {
        if (index == 0) {
            try blocks.append(allocator, .{
                .kind = .title,
                .line_start = 0,
                .line_count = 1,
            });
            index = 1;
            continue;
        }

        if (!poll_inserted and poll_height > 0 and isPlayersLine(lines[index])) {
            try blocks.append(allocator, .{
                .kind = .metadata,
                .line_start = index,
                .line_count = 1,
            });
            try blocks.append(allocator, .{
                .kind = .player_poll_table,
                .line_start = index + 1,
                .line_count = poll_height,
            });
            index += 1;
            poll_inserted = true;
            continue;
        }

        if (isDescriptionHeading(lines[index])) {
            try blocks.append(allocator, .{
                .kind = .description,
                .line_start = index,
                .line_count = lines.len - index,
            });
            break;
        }

        if (isPollTableLine(lines[index])) {
            const start = index;
            while (index < lines.len and isPollTableLine(lines[index])) : (index += 1) {}
            try blocks.append(allocator, .{
                .kind = .player_poll_table,
                .line_start = start,
                .line_count = index - start,
            });
            continue;
        }

        const start = index;
        while (index < lines.len and
            !isPollTableLine(lines[index]) and
            !isDescriptionHeading(lines[index]) and
            !(!poll_inserted and poll_height > 0 and isPlayersLine(lines[index]))) : (index += 1)
        {}
        try blocks.append(allocator, .{
            .kind = .metadata,
            .line_start = start,
            .line_count = index - start,
        });
    }

    return try blocks.toOwnedSlice(allocator);
}

pub fn buildViewportBlocks(allocator: std.mem.Allocator, blocks: []const Block) ![]const ui.BlockViewport.Block {
    const viewport_blocks = try allocator.alloc(ui.BlockViewport.Block, blocks.len);
    for (viewport_blocks, blocks) |*viewport_block, block| {
        viewport_block.* = .{ .height = block.height() };
    }
    return viewport_blocks;
}

pub const LineStyles = struct {
    title: chasen.TextStyle,
    label: chasen.TextStyle,
};

pub fn drawBlock(surface: *chasen.Surface, state: *const State, visible: ui.BlockViewport.VisibleBlock, styles: LineStyles) !void {
    if (visible.index >= state.blocks.len) return;
    const block = state.blocks[visible.index];

    switch (block.kind) {
        .title => drawTitleBlock(surface, state, block, visible.skip_rows, visible.max_rows, styles),
        .metadata => drawMetadataBlock(surface, state, block, visible.skip_rows, visible.max_rows, styles),
        .description => drawDescriptionBlock(surface, state, block, visible.skip_rows, visible.max_rows, styles),
        .player_poll_table => try drawPlayerPollTableBlock(surface, state, visible.skip_rows, visible.max_rows, styles),
    }
}

fn drawTitleBlock(surface: *chasen.Surface, state: *const State, block: Block, skip_rows: usize, max_rows: usize, styles: LineStyles) void {
    drawLineBlock(surface, state, block, skip_rows, max_rows, styles, drawTitleLine);
}

fn drawMetadataBlock(surface: *chasen.Surface, state: *const State, block: Block, skip_rows: usize, max_rows: usize, styles: LineStyles) void {
    drawLineBlock(surface, state, block, skip_rows, max_rows, styles, drawMetadataLine);
}

fn drawDescriptionBlock(surface: *chasen.Surface, state: *const State, block: Block, skip_rows: usize, max_rows: usize, styles: LineStyles) void {
    drawLineBlock(surface, state, block, skip_rows, max_rows, styles, drawDescriptionLine);
}

fn drawLineBlock(
    surface: *chasen.Surface,
    state: *const State,
    block: Block,
    skip_rows: usize,
    max_rows: usize,
    styles: LineStyles,
    comptime drawLineFn: fn (*chasen.Surface, u16, usize, []const u8, LineStyles) void,
) void {
    for (0..max_rows) |local_row| {
        const line_index = block.line_start + skip_rows + local_row;
        if (line_index >= state.lines.len) break;
        const row: u16 = @intCast(local_row);
        if (row >= surface.size().height) break;
        drawLineFn(surface, row, line_index - block.line_start, state.lines[line_index], styles);
    }
}

fn drawPlayerPollTableBlock(surface: *chasen.Surface, state: *const State, skip_rows: usize, max_rows: usize, styles: LineStyles) !void {
    const game = if (state.games.len > 0) state.games[0] else return;
    const poll = game.player_count_poll orelse return;
    if (poll.results.len == 0 or max_rows == 0) return;

    const allocator = surface.frameAllocator();
    var table_data = try playerPollTableData(allocator, poll, styles.label);
    if (table_data.rows.len == 0) return;

    var table_area = surface.child(.{
        .col = 0,
        .row = 0,
        .width = @min(surface.size().width, table_data.table.naturalWidthFor(0, .full) +| 10),
        .height = @intCast(@min(max_rows, @as(usize, surface.size().height))),
    });
    table_data.table.viewSlice(&table_area, .{
        .grid = .full,
        .grid_style = .rounded,
        .show_separator = true,
        .body_separators = false,
        .header_style = styles.label,
        .separator_style = .{},
        .cell_style = .{},
        .cell_padding = .{ .left = 1, .right = 1 },
    }, .{
        .skip_rows = skip_rows,
        .max_rows = max_rows,
    });
}

pub fn drawLine(surface: *chasen.Surface, row: u16, absolute_line_index: usize, line: []const u8, styles: LineStyles) void {
    if (absolute_line_index == 0) {
        drawTitleLine(surface, row, absolute_line_index, line, styles);
        return;
    }

    if (isPollTableLine(line)) {
        _ = surface.borrowTextAt(0, row, line, .{});
        return;
    }

    drawMetadataLine(surface, row, absolute_line_index, line, styles);
}

fn drawTitleLine(surface: *chasen.Surface, row: u16, local_line_index: usize, line: []const u8, styles: LineStyles) void {
    _ = local_line_index;
    _ = surface.borrowTextAt(0, row, line, styles.title);
}

fn drawMetadataLine(surface: *chasen.Surface, row: u16, local_line_index: usize, line: []const u8, styles: LineStyles) void {
    _ = local_line_index;
    if (detailLabelLength(line)) |label_len| {
        const label = line[0..label_len];
        _ = surface.borrowTextAt(0, row, label, styles.label);
        _ = surface.borrowTextAt(chasen.text.displayWidth(label), row, line[label_len..], .{});
        return;
    }

    _ = surface.borrowTextAt(0, row, line, .{});
}

fn drawDescriptionLine(surface: *chasen.Surface, row: u16, local_line_index: usize, line: []const u8, styles: LineStyles) void {
    if (local_line_index == 0) {
        _ = surface.borrowTextAt(0, row, line, styles.label);
        return;
    }

    _ = surface.borrowTextAt(0, row, line, .{});
}

pub fn lineStyle(line: []const u8) chasen.TextStyle {
    if (isDescriptionHeading(line)) return .{ .dim = true };
    return .{};
}

fn isDescriptionHeading(line: []const u8) bool {
    return std.mem.eql(u8, line, "Description");
}

fn isPlayersLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "Players");
}

fn isPollTableLine(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "  ┌") or
        std.mem.startsWith(u8, line, "  │") or
        std.mem.startsWith(u8, line, "  ├") or
        std.mem.startsWith(u8, line, "  └");
}

fn detailLabelLength(line: []const u8) ?usize {
    const labels = [_][]const u8{
        "Year",
        "Rating",
        "Geek Rating",
        "Rank",
        "Players",
        "Time",
        "Weight",
        "Age",
        "Owned",
        "Comments",
        "Designer",
        "Artist",
        "Categories",
        "Mechanics",
    };

    for (labels) |label| {
        if (std.mem.startsWith(u8, line, label)) return label.len;
    }
    return null;
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
    try std.testing.expect(std.mem.indexOf(u8, text, "  ┌") == null);
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
    try std.testing.expect(!lineStyle("  │ 5+ │ 1 (50%) │  0 (0%) │  1 (50%) │").dim);
    try std.testing.expect(lineStyle("Description").dim);
}

test "detail draw line colors title labels and tables" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(40, 4);
    defer ts.deinit();

    const accent = chasen.Color{ .rgb = .{ 203, 166, 247 } };
    const styles = LineStyles{
        .title = .{ .fg = accent, .bold = true },
        .label = .{ .fg = accent, .bold = true },
    };

    drawLine(&ts.surface, 0, 0, "CATAN", styles);
    drawLine(&ts.surface, 1, 2, "Rating       7.14", styles);
    drawLine(&ts.surface, 2, 4, "  │    │ Best │", styles);
    drawLine(&ts.surface, 3, 5, "Trade resources", styles);

    try std.testing.expect(ts.surface.readCell(0, 0).?.style.fg.eql(accent.toVaxis()));
    try std.testing.expect(ts.surface.readCell(0, 1).?.style.fg.eql(accent.toVaxis()));
    try std.testing.expect(!ts.surface.readCell(13, 1).?.style.fg.eql(accent.toVaxis()));
    try std.testing.expect(!ts.surface.readCell(2, 2).?.style.fg.eql(accent.toVaxis()));
    try std.testing.expect(!ts.surface.readCell(2, 2).?.style.dim);
    try std.testing.expect(!ts.surface.readCell(0, 3).?.style.fg.eql(accent.toVaxis()));
}

test "detail blocks split title metadata poll table and description" {
    const lines = [_][]const u8{
        "CATAN",
        "",
        "Year         1995",
        "  ┌────┬──────┐",
        "  │    │ Best │",
        "  └────┴──────┘",
        "Weight       2.32 / 5 - Medium",
        "",
        "Description",
        "Trade resources.",
        "",
        "Settle the island.",
    };

    const blocks = try buildBlocks(std.testing.allocator, &lines);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 5), blocks.len);
    try std.testing.expectEqual(Block.Kind.title, blocks[0].kind);
    try std.testing.expectEqual(@as(usize, 0), blocks[0].line_start);
    try std.testing.expectEqual(@as(usize, 1), blocks[0].line_count);
    try std.testing.expectEqual(Block.Kind.metadata, blocks[1].kind);
    try std.testing.expectEqual(@as(usize, 1), blocks[1].line_start);
    try std.testing.expectEqual(@as(usize, 2), blocks[1].line_count);
    try std.testing.expectEqual(Block.Kind.player_poll_table, blocks[2].kind);
    try std.testing.expectEqual(@as(usize, 3), blocks[2].line_start);
    try std.testing.expectEqual(@as(usize, 3), blocks[2].line_count);
    try std.testing.expectEqual(Block.Kind.metadata, blocks[3].kind);
    try std.testing.expectEqual(@as(usize, 6), blocks[3].line_start);
    try std.testing.expectEqual(@as(usize, 2), blocks[3].line_count);
    try std.testing.expectEqual(Block.Kind.description, blocks[4].kind);
    try std.testing.expectEqual(@as(usize, 8), blocks[4].line_start);
    try std.testing.expectEqual(@as(usize, 4), blocks[4].line_count);
}

test "detail blocks insert poll table after players line" {
    var poll_results = [_]bgg_model.PlayerCountVotes{
        .{ .num_players = "1", .best = 0, .recommended = 0, .not_recommended = 3 },
        .{ .num_players = "2", .best = 2, .recommended = 1, .not_recommended = 2 },
    };
    const game = bgg_model.Game{
        .id = 13,
        .name = "CATAN",
        .player_count_poll = .{ .results = &poll_results },
    };
    const lines = [_][]const u8{
        "CATAN",
        "",
        "Year         1995",
        "Players      3-4",
        "Time         120 min",
        "",
        "Description",
        "Trade resources.",
    };

    const blocks = try buildBlocksForGame(std.testing.allocator, &lines, game);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 6), blocks.len);
    try std.testing.expectEqual(Block.Kind.title, blocks[0].kind);
    try std.testing.expectEqual(Block.Kind.metadata, blocks[1].kind);
    try std.testing.expectEqual(@as(usize, 1), blocks[1].line_start);
    try std.testing.expectEqual(@as(usize, 2), blocks[1].line_count);
    try std.testing.expectEqual(Block.Kind.metadata, blocks[2].kind);
    try std.testing.expectEqual(@as(usize, 3), blocks[2].line_start);
    try std.testing.expectEqual(@as(usize, 1), blocks[2].line_count);
    try std.testing.expectEqual(Block.Kind.player_poll_table, blocks[3].kind);
    try std.testing.expectEqual(@as(usize, 4), blocks[3].line_start);
    try std.testing.expectEqual(@as(usize, 6), blocks[3].line_count);
    try std.testing.expectEqual(Block.Kind.metadata, blocks[4].kind);
    try std.testing.expectEqual(@as(usize, 4), blocks[4].line_start);
    try std.testing.expectEqual(@as(usize, 2), blocks[4].line_count);
    try std.testing.expectEqual(Block.Kind.description, blocks[5].kind);
    try std.testing.expectEqual(@as(usize, 6), blocks[5].line_start);
    try std.testing.expectEqual(@as(usize, 2), blocks[5].line_count);
}

test "detail description block colors heading only" {
    const detail_text = "CATAN\nDescription\nTrade resources.";
    const lines = try splitOwnedLines(std.testing.allocator, detail_text);
    defer std.testing.allocator.free(lines);

    var state: State = .{
        .rendered_text = try std.testing.allocator.dupe(u8, detail_text),
        .lines = lines,
        .blocks = try buildBlocks(std.testing.allocator, lines),
    };
    defer {
        std.testing.allocator.free(state.rendered_text);
        std.testing.allocator.free(state.blocks);
    }

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(32, 2);
    defer ts.deinit();

    const accent = chasen.Color{ .rgb = .{ 203, 166, 247 } };
    try drawBlock(&ts.surface, &state, .{
        .index = 1,
        .skip_rows = 0,
        .max_rows = 2,
        .row = 0,
    }, .{
        .title = .{ .bold = true },
        .label = .{ .fg = accent, .bold = true },
    });

    try std.testing.expect(ts.surface.readCell(0, 0).?.style.fg.eql(accent.toVaxis()));
    try std.testing.expect(!ts.surface.readCell(0, 1).?.style.fg.eql(accent.toVaxis()));
}

test "detail poll table block draws recommendation markers" {
    var poll_results = try std.testing.allocator.alloc(bgg_model.PlayerCountVotes, 3);
    poll_results[0] = .{ .num_players = try std.testing.allocator.dupe(u8, "2"), .best = 8, .recommended = 2, .not_recommended = 1 };
    poll_results[1] = .{ .num_players = try std.testing.allocator.dupe(u8, "3"), .best = 2, .recommended = 8, .not_recommended = 1 };
    poll_results[2] = .{ .num_players = try std.testing.allocator.dupe(u8, "4"), .best = 3, .recommended = 3, .not_recommended = 1 };
    var games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "CATAN"),
        .player_count_poll = .{ .results = poll_results },
    };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games, 80);
    defer state.deinit(std.testing.allocator);

    var block_index: usize = 0;
    while (block_index < state.blocks.len and state.blocks[block_index].kind != .player_poll_table) : (block_index += 1) {}
    try std.testing.expect(block_index < state.blocks.len);

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(48, 8);
    defer ts.deinit();

    const accent = chasen.Color{ .rgb = .{ 203, 166, 247 } };
    try drawBlock(&ts.surface, &state, .{
        .index = block_index,
        .skip_rows = 0,
        .max_rows = state.blocks[block_index].height(),
        .row = 0,
    }, .{
        .title = .{ .bold = true },
        .label = .{ .fg = accent, .bold = true },
    });

    try std.testing.expect(ts.surface.readCell(0, 2).?.char.grapheme.len > 0);
    try expectStyledStarOnRow(&ts.surface, 3, accent);
    try expectStyledStarOnRow(&ts.surface, 4, accent);

    var partial_ts: chasen.testing.TestSurface = undefined;
    try partial_ts.init(48, 2);
    defer partial_ts.deinit();

    try drawBlock(&partial_ts.surface, &state, .{
        .index = block_index,
        .skip_rows = 3,
        .max_rows = 2,
        .row = 0,
    }, .{
        .title = .{ .bold = true },
        .label = .{ .fg = accent, .bold = true },
    });
    try expectStyledStarOnRow(&partial_ts.surface, 0, accent);
}

fn expectStyledStarOnRow(surface: *const chasen.Surface, row: u16, color: chasen.Color) !void {
    var col: u16 = 0;
    while (col < surface.size().width) : (col += 1) {
        const cell = surface.readCell(col, row) orelse continue;
        if (!std.mem.eql(u8, cell.char.grapheme, "★")) continue;
        try std.testing.expect(cell.style.fg.eql(color.toVaxis()));
        return;
    }
    return error.TestExpectedStyledStar;
}

test "player count poll table height skips polls without vote rows" {
    var poll_results = [_]bgg_model.PlayerCountVotes{
        .{ .num_players = "1" },
        .{ .num_players = "2" },
    };
    const poll = bgg_model.PlayerCountPoll{ .results = &poll_results };

    try std.testing.expectEqual(@as(usize, 0), playerPollTableRenderedRowCount(poll));
}
