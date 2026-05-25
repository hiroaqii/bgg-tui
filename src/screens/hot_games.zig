const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const list_sort = @import("../list_sort.zig");
const task_bgg = @import("../tasks/bgg.zig");

const filter_row: u16 = 4;

pub const Result = task_bgg.HotGamesResult;
pub const StatsResult = task_bgg.HotGameStatsResult;

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
