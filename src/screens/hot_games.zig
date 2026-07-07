const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const column_list_view = @import("../column_list_view.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const list_view = @import("../list_view.zig");
const motion = @import("../motion.zig");
const paste = @import("../paste.zig");
const list_sort = @import("../list_sort.zig");
const shortcuts = @import("../shortcuts.zig");
const task_bgg = @import("../tasks/bgg.zig");

const filter_row: u16 = 4;
const position_row: u16 = 2;
const body_row: u16 = 4;
const filtered_body_row: u16 = 6;
const footer_gap: u16 = 1;
const stats_legend = "trending games  ★ Rating  ⚖ Weight  #Rank";
const hot_columns = [_]ui.ColumnList.Column{
    .{ .width = .{ .fixed = 4 } },
    .{ .width = .flex },
    .{ .width = .{ .fixed = 1 }, .alignment = .right },
    .{ .width = .{ .fixed = 5 } },
    .{ .width = .{ .fixed = 1 }, .alignment = .right },
    .{ .width = .{ .fixed = 5 } },
    .{ .width = .{ .fixed = 6 }, .alignment = .right },
};

const HotColumnContext = struct {
    state: *const State,
    accent: chasen.Color,
};

pub const Result = task_bgg.HotGamesResult;
pub const StatsResult = task_bgg.HotGameStatsResult;

pub const ViewOptions = struct {
    title_style: chasen.TextStyle,
    focused_style: chasen.TextStyle,
    muted_style: chasen.TextStyle,
    subtle_style: chasen.TextStyle,
    accent: chasen.Color,
    footer_items: []const ui.key_hint.Item,
    list_density: list_view.Density,
    selection: []const u8,
    animation_frame: u64,
    loading_scan_frame: u64,
    image_panel_rect: ?chasen.Rect = null,
    image_panel_gap: u16 = 0,
};

pub const Msg = union(enum) {
    filter_start,
    filter_input: ui.TextInput.Msg,
    filter_paste: []const u8,
    filter_clear,
    list: ui.List.Msg,
    sort_toggle,
    loaded: Result,
    stats_loaded: StatsResult,
};

pub const Action = union(enum) {
    none,
    preview_changed,
    open_game: usize,
    loaded: Result,
    stats_loaded: StatsResult,
};

pub const State = struct {
    filter_input: ?ui.TextInput = null,
    load_state: LoadState = .idle,
    games: []bgg_model.HotGame = &.{},
    stats: []bgg_model.Game = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    sort_mode: list_sort.Mode = .source,
    sorted_source_indexes: []usize = &.{},
    sorted_labels: []const []const u8 = &.{},
    sorted_list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,
    request_id: u64 = 0,

    pub const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    pub fn initInputs(self: *State, allocator: std.mem.Allocator) !void {
        self.filter_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Filter hot games",
        });
    }

    pub fn deinitInputs(self: *State) void {
        if (self.filter_input) |*input| {
            input.deinit();
            self.filter_input = null;
        }
    }

    pub fn setLoading(self: *State) void {
        self.request_id +%= 1;
        self.load_state = .loading;
    }

    pub fn setFailed(self: *State, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    pub fn setLoaded(self: *State, allocator: std.mem.Allocator, games: []bgg_model.HotGame) !void {
        self.deinit(allocator);
        self.games = games;
        self.labels = try labels_mod.buildHotGameLabels(allocator, games);
        self.list = ui.List.init(.{ .items = self.labels });
        self.load_state = .loaded;
    }

    pub fn setStatsLoaded(self: *State, allocator: std.mem.Allocator, stats: []bgg_model.Game) !void {
        const focused_source_index = self.sourceIndex(self.activeList().focusedIndex());

        bgg_xml.freeGames(allocator, self.stats);
        self.stats = stats;

        const filter_was_active = self.filter_active;
        const filter_query = if (filter_was_active) try allocator.dupe(u8, self.filter.query) else &.{};
        defer if (filter_was_active) allocator.free(filter_query);

        labels_mod.freeHotGameLabels(allocator, self.labels);
        self.freeSortedList(allocator);
        self.filter.deinit(allocator);

        self.labels = try labels_mod.buildHotGameLabelsWithStats(allocator, self.games, self.stats);
        self.list = ui.List.init(.{ .items = self.labels });

        if (self.sort_mode != .source) try self.rebuildSortedList(allocator, self.sort_mode);
        if (filter_was_active) {
            try self.applyFilter(allocator, filter_query);
        } else {
            self.filter_active = false;
        }
        if (focused_source_index) |source_index| self.focusSourceIndex(source_index);
    }

    pub fn update(self: *State, msg: ui.List.Msg) void {
        if (self.filter_active) {
            self.filter.update(msg);
        } else if (self.sort_mode != .source) {
            self.sorted_list.update(msg);
        } else {
            self.list.update(msg);
        }
    }

    pub fn handleEvent(self: *const State, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        if (self.filter_active) return self.filter.handleEvent(event);
        if (self.sort_mode != .source) return self.sorted_list.handleEvent(event);
        return self.list.handleEvent(event);
    }

    pub fn handleScreenEvent(self: *const State, event: chasen.Event) ?Msg {
        if (self.filter_active) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{})) return .filter_clear;
                    if (key.matches(chasen.Key.enter, .{})) {
                        if (self.handleEvent(event)) |msg| return .{ .list = msg };
                        return null;
                    }
                },
                .paste => |text| return .{ .filter_paste = text },
                else => {},
            }
            if (self.filter_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .filter_input = msg };
            }
            if (self.handleEvent(event)) |msg| return .{ .list = msg };
            return null;
        }

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == '/') return .filter_start;
                if (key.codepoint == 's') return .sort_toggle;
                if (shortcuts.vimListMove(key)) |msg| return .{ .list = msg };
            },
            else => {},
        }

        if (self.handleEvent(event)) |msg| return .{ .list = msg };
        return null;
    }

    pub fn activeList(self: *const State) *const ui.List {
        if (self.filter_active) return &self.filter.list;
        if (self.sort_mode != .source) return &self.sorted_list;
        return &self.list;
    }

    pub fn sourceIndex(self: *const State, visible_index: usize) ?usize {
        if (self.filter_active) return self.filter.sourceIndex(visible_index);
        if (self.sort_mode != .source) {
            if (visible_index >= self.sorted_source_indexes.len) return null;
            return self.sorted_source_indexes[visible_index];
        }
        if (visible_index >= self.games.len) return null;
        return visible_index;
    }

    pub fn focusSourceIndex(self: *State, source_index: usize) void {
        if (self.filter_active) {
            for (self.filter.source_indexes, 0..) |filter_source_index, visible_index| {
                if (filter_source_index == source_index) {
                    self.filter.list.focus.index = visible_index;
                    return;
                }
            }
            return;
        }
        if (self.sort_mode != .source) {
            for (self.sorted_source_indexes, 0..) |sorted_source_index, visible_index| {
                if (sorted_source_index == source_index) {
                    self.sorted_list.focus.index = visible_index;
                    return;
                }
            }
            return;
        }
        if (source_index < self.list.items.len) self.list.focus.index = source_index;
    }

    pub fn applyFilter(self: *State, allocator: std.mem.Allocator, query: []const u8) !void {
        if (self.sort_mode == .source) {
            try self.filter.apply(allocator, self.labels, query);
        } else {
            try self.filter.applyWithSourceIndexes(allocator, self.sorted_labels, self.sorted_source_indexes, query);
        }
        self.filter_active = true;
    }

    pub fn clearFilter(self: *State, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    pub fn toggleSort(self: *State, allocator: std.mem.Allocator) !void {
        if (self.load_state != .loaded) return;

        const next_mode = self.sort_mode.next();
        if (next_mode != .source) {
            try self.rebuildSortedList(allocator, next_mode);
        } else {
            self.freeSortedList(allocator);
        }

        self.sort_mode = next_mode;
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    pub fn updateScreen(self: *State, allocator: std.mem.Allocator, msg: Msg) !Action {
        switch (msg) {
            .filter_start => {
                try self.startFilter(allocator);
                return .preview_changed;
            },
            .filter_input => |input_msg| {
                if (input_msg == .submit) return .none;
                if (self.filter_input) |*input| try input.update(input_msg);
                try self.applyFilterFromInput(allocator);
                return .preview_changed;
            },
            .filter_paste => |text| {
                if (self.filter_input) |*input| {
                    try paste.insertCodepoints(input, text);
                    try self.applyFilterFromInput(allocator);
                    return .preview_changed;
                }
                return .none;
            },
            .filter_clear => {
                try self.clearFilterInput(allocator);
                return .preview_changed;
            },
            .list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => {
                    self.update(list_msg);
                    return .preview_changed;
                },
                .activate => |index| {
                    if (self.sourceIndex(index)) |source_index| return .{ .open_game = source_index };
                    return .none;
                },
            },
            .sort_toggle => {
                try self.toggleSort(allocator);
                return .preview_changed;
            },
            .loaded => |result| return .{ .loaded = result },
            .stats_loaded => |result| return .{ .stats_loaded = result },
        }
    }

    fn startFilter(self: *State, allocator: std.mem.Allocator) !void {
        if (self.filter_input) |*input| try input.update(.clear);
        try self.applyFilter(allocator, "");
    }

    fn applyFilterFromInput(self: *State, allocator: std.mem.Allocator) !void {
        const input = if (self.filter_input) |*input| input else return;
        try self.applyFilter(allocator, input.text());
    }

    fn clearFilterInput(self: *State, allocator: std.mem.Allocator) !void {
        if (self.filter_input) |*input| try input.update(.clear);
        self.clearFilter(allocator);
    }

    pub fn drawFilterInput(self: *const State, surface: *chasen.Surface, style: chasen.TextStyle) void {
        _ = surface.borrowTextAt(0, filter_row, "Filter:", style);
        if (self.filter_input) |*input| {
            var input_area = surface.child(.{
                .col = 8,
                .row = filter_row,
                .width = surface.size().width -| 8,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    pub fn view(self: *const State, area: *chasen.Surface, opts: ViewOptions) !?chasen.Rect {
        if (!self.filter_active) area.hideCursor();

        _ = try area.printAt(0, 0, opts.title_style, "Hot Games ({s})", .{self.sort_mode.label(.hot_games)});

        const image_rect = switch (self.load_state) {
            .idle, .loading => image_rect: {
                drawCenteredLoadingGuidance(area, "Hot Games", "Loading BoardGameGeek hot games...", opts.muted_style, opts.loading_scan_frame);
                break :image_rect null;
            },
            .failed => |message| image_rect: {
                drawCenteredGuidance(area, "Could not load hot games.", message);
                break :image_rect null;
            },
            .loaded => image_rect: {
                if (self.list.items.len == 0) {
                    drawCenteredGuidance(area, "No hot games", "BGG did not return any hot games.");
                    break :image_rect null;
                }
                if (self.filter_active and self.filter.labels.len == 0) {
                    self.drawFilterInput(area, opts.subtle_style);
                    drawCenteredGuidanceKeepingCursor(area, "No matches", "No hot games match the filter.");
                    break :image_rect null;
                }

                const current_body_row = if (self.filter_active) filtered_body_row else body_row;
                if (self.filter_active) self.drawFilterInput(area, opts.subtle_style);

                const list = self.activeList();
                const list_width = if (opts.image_panel_rect) |rect| rect.col -| opts.image_panel_gap else area.size().width;
                var list_area = area.child(.{
                    .col = 0,
                    .row = current_body_row,
                    .width = list_width,
                    .height = area.size().height -| (current_body_row + 1 + footer_gap),
                });
                try self.drawHotColumnList(list, &list_area, opts);

                try drawListPositionWithLegend(area, list, stats_legend, opts.subtle_style);
                drawSortMode(area, self.sort_mode.label(.hot_games), opts.subtle_style);
                break :image_rect opts.image_panel_rect;
            },
        };

        _ = try ui.key_hint.draw(area, 0, area.size().height -| 1, opts.footer_items, .{ .style = opts.subtle_style });
        return image_rect;
    }

    fn drawHotColumnList(self: *const State, list: *const ui.List, surface: *chasen.Surface, opts: ViewOptions) !void {
        const column_context: HotColumnContext = .{
            .state = self,
            .accent = opts.accent,
        };
        try column_list_view.viewVisibleRows(list, surface, &hot_columns, &column_context, buildHotColumnRow, .{
            .focused_style = opts.focused_style,
            .selection = opts.selection,
            .animation_frame = opts.animation_frame,
            .column_gap = 1,
            .show_cursor = false,
        });
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.freeSortedList(allocator);
        labels_mod.freeHotGameLabels(allocator, self.labels);
        bgg_xml.freeGames(allocator, self.stats);
        bgg_xml.freeHotGames(allocator, self.games);
        self.labels = &.{};
        self.stats = &.{};
        self.games = &.{};
        self.list = ui.List.init(.{});
        self.sort_mode = .source;
        self.filter_active = false;
        self.load_state = .idle;
    }

    fn rebuildSortedList(self: *State, allocator: std.mem.Allocator, mode: list_sort.Mode) !void {
        const indexes = try allocator.alloc(usize, self.games.len);
        errdefer allocator.free(indexes);
        for (indexes, 0..) |*index, value| index.* = value;

        switch (mode) {
            .source => {},
            .name_asc => std.mem.sort(usize, indexes, self.games, hotGameNameLessThan),
        }

        const labels = try allocator.alloc([]const u8, indexes.len);
        errdefer allocator.free(labels);
        for (indexes, 0..) |source_index, display_index| {
            labels[display_index] = self.labels[source_index];
        }

        self.freeSortedList(allocator);
        self.sorted_source_indexes = indexes;
        self.sorted_labels = labels;
        self.sorted_list = ui.List.init(.{ .items = self.sorted_labels });
    }

    fn freeSortedList(self: *State, allocator: std.mem.Allocator) void {
        allocator.free(self.sorted_source_indexes);
        allocator.free(self.sorted_labels);
        self.sorted_source_indexes = &.{};
        self.sorted_labels = &.{};
        self.sorted_list = ui.List.init(.{});
    }
};

fn buildHotColumnRow(context: *const anyopaque, allocator: std.mem.Allocator, visible_index: usize) !ui.ColumnList.Row {
    const column_context: *const HotColumnContext = @ptrCast(@alignCast(context));
    const state = column_context.state;
    const source_index = state.sourceIndex(visible_index) orelse return &.{};
    return hotColumnRow(allocator, state.games[source_index], hotStatsFor(state.stats, state.games[source_index].id), column_context.accent);
}

fn hotColumnRow(allocator: std.mem.Allocator, game: bgg_model.HotGame, stats: ?bgg_model.Game, accent: chasen.Color) !ui.ColumnList.Row {
    const row = try allocator.alloc(ui.ColumnList.Cell, hot_columns.len);
    row[0] = .{ .text = try std.fmt.allocPrint(allocator, "#{d}", .{game.rank}), .style = .{ .fg = accent } };
    row[1] = .{ .text = try hotGameName(allocator, game) };
    if (stats) |game_stats| {
        row[2] = .{ .text = "★", .style = .{ .fg = accent } };
        row[3] = .{ .text = try gameRatingText(allocator, game_stats.rating) };
        row[4] = .{ .text = "⚖", .style = .{ .fg = accent } };
        row[5] = .{ .text = try gameRatingText(allocator, game_stats.weight) };
        row[6] = .{ .text = try gameRankText(allocator, game_stats.rank) };
    } else {
        row[2] = .{ .text = "" };
        row[3] = .{ .text = "" };
        row[4] = .{ .text = "" };
        row[5] = .{ .text = "" };
        row[6] = .{ .text = "" };
    }
    return row;
}

fn hotGameName(allocator: std.mem.Allocator, game: bgg_model.HotGame) ![]const u8 {
    if (game.year_published) |year| {
        return try std.fmt.allocPrint(allocator, "{s} ({d})", .{ game.name, year });
    }
    return game.name;
}

fn gameRatingText(allocator: std.mem.Allocator, rating: f64) ![]const u8 {
    if (rating <= 0) return "-";
    return try std.fmt.allocPrint(allocator, "{d:.2}", .{rating});
}

fn gameRankText(allocator: std.mem.Allocator, rank: u32) ![]const u8 {
    if (rank == 0) return "    -";
    return try std.fmt.allocPrint(allocator, "#{d}", .{rank});
}

fn hotStatsFor(stats: []const bgg_model.Game, id: u32) ?bgg_model.Game {
    for (stats) |game| {
        if (game.id == id) return game;
    }
    return null;
}

fn drawListPositionWithLegend(surface: *chasen.Surface, list: *const ui.List, legend: []const u8, style: chasen.TextStyle) !void {
    const item_count = list.items.len;
    if (item_count == 0 or surface.size().height < 2) return;

    const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
    _ = try surface.printAt(0, position_row, style, "{s} {s}", .{ text, legend });
}

fn drawSortMode(surface: *chasen.Surface, label: []const u8, style: chasen.TextStyle) void {
    if (surface.size().width <= 12 or surface.size().height <= position_row) return;
    _ = surface.borrowTextAt(10, position_row, label, style);
}

fn drawCenteredGuidance(surface: *chasen.Surface, title: []const u8, message: []const u8) void {
    const block = ui.MessageBlock.init(.{ .title = title, .message = message });
    block.view(surface, .{});
}

fn drawCenteredLoadingGuidance(surface: *chasen.Surface, title: []const u8, message: []const u8, style: chasen.TextStyle, frame: u64) void {
    const block = ui.MessageBlock.init(.{ .title = title, .message = message });
    block.view(surface, .{});
    if (block.layout(surface.size()).message) |point| {
        motion.drawStatusScanText(surface, point.col, point.row, message, style, frame);
    }
}

fn drawCenteredGuidanceKeepingCursor(surface: *chasen.Surface, title: []const u8, message: []const u8) void {
    const block = ui.MessageBlock.init(.{ .title = title, .message = message });
    block.view(surface, .{ .hide_cursor = false });
}

fn hotGameNameLessThan(games: []const bgg_model.HotGame, lhs: usize, rhs: usize) bool {
    const order = compareAsciiIgnoreCase(games[lhs].name, games[rhs].name);
    if (order == .eq) return lhs < rhs;
    return order == .lt;
}

fn compareAsciiIgnoreCase(lhs: []const u8, rhs: []const u8) std.math.Order {
    const len = @min(lhs.len, rhs.len);
    for (lhs[0..len], rhs[0..len]) |lhs_byte, rhs_byte| {
        const left = std.ascii.toLower(lhs_byte);
        const right = std.ascii.toLower(rhs_byte);
        if (left < right) return .lt;
        if (left > right) return .gt;
    }
    return std.math.order(lhs.len, rhs.len);
}

test "hot games state owns labels for loaded games" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "First") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Second"), .year_published = 2024 };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 2), state.list.items.len);
    try std.testing.expectEqualStrings("#1   First", state.list.items[0]);
    try std.testing.expectEqualStrings("#2   Second (2024)", state.list.items[1]);
}

test "hot games filter maps visible focus back to source index" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expect(state.filter_active);
    try std.testing.expectEqual(@as(usize, 2), state.filter.labels.len);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "hot games name sort preserves source index activation" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try std.testing.expectEqual(list_sort.Mode.name_asc, state.sort_mode);
    try std.testing.expectEqualStrings("#2   Cascadia", state.activeList().items[0]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
}

test "hot games sorted projection owns movement and activation" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 0), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 1 }, state.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?);
}

test "hot games vim movement stays out of filter text input" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    defer {
        state.deinitInputs();
        state.deinit(std.testing.allocator);
    }

    const move_msg = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'j' } }).?;
    try std.testing.expectEqual(Msg{ .list = .move_next }, move_msg);

    try state.applyFilter(std.testing.allocator, "");
    const input_msg = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'j', .text = "j" } }).?;
    try std.testing.expect(input_msg == .filter_input);
    try std.testing.expectEqual(ui.TextInput.Msg{ .insert = 'j' }, input_msg.filter_input);
}

test "hot games focus clamps in source and sorted projections" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());

    try state.toggleSort(std.testing.allocator);
    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
}

test "hot games sort failure keeps existing projection state" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, state.toggleSort(failing_allocator.allocator()));

    try std.testing.expectEqual(list_sort.Mode.source, state.sort_mode);
    try std.testing.expectEqual(@as(usize, 0), state.sorted_source_indexes.len);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().items.len);
    try std.testing.expectEqualStrings("#1   Root", state.activeList().items[0]);
}

test "hot games filter uses current name sort order" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try state.applyFilter(std.testing.allocator, "ca");

    try std.testing.expectEqualStrings("#2   Cascadia", state.activeList().items[0]);
    try std.testing.expectEqualStrings("#3   CATAN", state.activeList().items[1]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(1).?);
}

test "hot games stats refresh preserves filtered focus" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);

    const stats = try std.testing.allocator.alloc(bgg_model.Game, 3);
    stats[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root"), .rating = 8.1 };
    stats[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia"), .rating = 7.5 };
    stats[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN"), .rating = 7.2 };
    try state.setStatsLoaded(std.testing.allocator, stats);

    const focused_index = state.activeList().focusedIndex();
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(focused_index).?);
    try std.testing.expectEqualStrings("#3   CATAN     ★  7.20  ⚖     -      -", state.activeList().items[focused_index]);
}

test "hot games screen event starts filter and sort" {
    var state: State = .{};

    const filter_msg = state.handleScreenEvent(.{ .key_press = .{ .codepoint = '/' } }).?;
    try std.testing.expect(filter_msg == .filter_start);

    const sort_msg = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 's' } }).?;
    try std.testing.expect(sort_msg == .sort_toggle);
}

test "hot games screen event routes active filter input" {
    var state: State = .{};
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    defer state.deinitInputs();

    try state.applyFilter(std.testing.allocator, "");
    defer state.clearFilter(std.testing.allocator);

    const paste_msg = state.handleScreenEvent(.{ .paste = "root" }).?;
    try std.testing.expect(paste_msg == .filter_paste);
    try std.testing.expectEqualStrings("root", paste_msg.filter_paste);

    const clear_msg = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(clear_msg == .filter_clear);
}

test "hot games update screen reports preview changes for filter and movement" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: State = .{};
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    try state.setLoaded(std.testing.allocator, games);
    defer {
        state.deinitInputs();
        state.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(Action.preview_changed, try state.updateScreen(std.testing.allocator, .filter_start));
    try std.testing.expectEqual(Action.preview_changed, try state.updateScreen(std.testing.allocator, .{ .filter_paste = "ca" }));
    try std.testing.expectEqualStrings("ca", state.filter_input.?.text());
    try std.testing.expect(state.filter_active);

    try std.testing.expectEqual(Action.preview_changed, try state.updateScreen(std.testing.allocator, .{ .list = .move_next }));
    const action = try state.updateScreen(std.testing.allocator, .{ .list = .{ .activate = state.activeList().focusedIndex() } });
    try std.testing.expect(action == .open_game);
    try std.testing.expectEqual(@as(usize, 1), action.open_game);
}

test "hot games update screen strips control characters from paste" {
    var state: State = .{};
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    defer state.deinitInputs();

    try state.applyFilter(std.testing.allocator, "");
    defer state.clearFilter(std.testing.allocator);

    try std.testing.expectEqual(Action.preview_changed, try state.updateScreen(std.testing.allocator, .{ .filter_paste = "Catan\n\tDuel" }));
    try std.testing.expectEqualStrings("CatanDuel", state.filter_input.?.text());
}

test "hot games update screen keeps async results as app actions" {
    var state: State = .{};

    const loaded = try state.updateScreen(std.testing.allocator, .{ .loaded = .{ .failed = "no token" } });
    try std.testing.expect(loaded == .loaded);

    const stats_loaded = try state.updateScreen(std.testing.allocator, .{ .stats_loaded = .{
        .request_id = 1,
        .result = .{ .failed = "missing" },
    } });
    try std.testing.expect(stats_loaded == .stats_loaded);
}
