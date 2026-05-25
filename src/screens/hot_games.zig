const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const list_sort = @import("../list_sort.zig");
const task_bgg = @import("../tasks/bgg.zig");

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
