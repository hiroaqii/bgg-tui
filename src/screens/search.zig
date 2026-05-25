const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const list_sort = @import("../list_sort.zig");
const task_bgg = @import("../tasks/bgg.zig");

pub const Result = task_bgg.SearchResult;
pub const TaskResult = task_bgg.SearchTaskResult;

pub const Msg = union(enum) {
    input: ui.TextInput.Msg,
    paste: []const u8,
    filter_start,
    filter_input: ui.TextInput.Msg,
    filter_paste: []const u8,
    filter_clear,
    sort_toggle,
    results_loaded: TaskResult,
    list: ui.List.Msg,
};

pub const State = struct {
    input: ?ui.TextInput = null,
    filter_input: ?ui.TextInput = null,
    request_id: u64 = 0,
    load_state: LoadState = .idle,
    results: []bgg_model.GameSearchResult = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    sort_mode: list_sort.Mode = .source,
    sorted_source_indexes: []usize = &.{},
    sorted_labels: []const []const u8 = &.{},
    sorted_list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,

    pub const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    pub fn initInputs(self: *State, allocator: std.mem.Allocator) !void {
        self.input = try ui.TextInput.init(allocator, .{
            .placeholder = "Search board games",
        });
        errdefer {
            self.input.?.deinit();
            self.input = null;
        }
        self.filter_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Filter search results",
        });
    }

    pub fn deinitInputs(self: *State) void {
        if (self.input) |*input| {
            input.deinit();
            self.input = null;
        }
        if (self.filter_input) |*input| {
            input.deinit();
            self.filter_input = null;
        }
    }

    pub fn setLoading(self: *State, allocator: std.mem.Allocator) void {
        self.clearResults(allocator);
        self.load_state = .loading;
    }

    pub fn setFailed(self: *State, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearResults(allocator);
        self.load_state = .{ .failed = message };
    }

    pub fn setLoaded(self: *State, allocator: std.mem.Allocator, results: []bgg_model.GameSearchResult) !void {
        self.clearResults(allocator);
        self.results = results;
        self.labels = try labels_mod.buildSearchResultLabels(allocator, results);
        self.list = ui.List.init(.{ .items = self.labels });
        self.load_state = .loaded;
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
        if (visible_index >= self.results.len) return null;
        return visible_index;
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
        self.clearResults(allocator);
        self.load_state = .idle;
    }

    fn rebuildSortedList(self: *State, allocator: std.mem.Allocator, mode: list_sort.Mode) !void {
        const indexes = try allocator.alloc(usize, self.results.len);
        errdefer allocator.free(indexes);
        for (indexes, 0..) |*index, value| index.* = value;

        switch (mode) {
            .source => {},
            .name_asc => std.mem.sort(usize, indexes, self.results, searchResultNameLessThan),
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

    fn clearResults(self: *State, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.freeSortedList(allocator);
        labels_mod.freeSearchResultLabels(allocator, self.labels);
        bgg_xml.freeSearchResults(allocator, self.results);
        self.labels = &.{};
        self.results = &.{};
        self.list = ui.List.init(.{});
        self.sort_mode = .source;
        self.filter_active = false;
    }
};

fn searchResultNameLessThan(results: []const bgg_model.GameSearchResult, lhs: usize, rhs: usize) bool {
    const order = compareAsciiIgnoreCase(results[lhs].name, results[rhs].name);
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

test "search state owns labels for loaded results" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 2);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "First") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Second"), .year_published = 2024 };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 2), state.list.items.len);
    try std.testing.expectEqualStrings("First", state.list.items[0]);
    try std.testing.expectEqualStrings("Second (2024)", state.list.items[1]);
}

test "search results filter maps visible focus back to source index" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expect(state.filter_active);
    try std.testing.expectEqual(@as(usize, 2), state.filter.labels.len);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "search results name sort preserves source index activation" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try std.testing.expectEqual(list_sort.Mode.name_asc, state.sort_mode);
    try std.testing.expectEqualStrings("Cascadia", state.activeList().items[0]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
}

test "search results sorted projection owns movement and activation" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 0), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 1 }, state.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?);
}

test "search results focus clamps in source and sorted projections" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 2);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
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

test "search results sort failure keeps existing projection state" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, state.toggleSort(failing_allocator.allocator()));

    try std.testing.expectEqual(list_sort.Mode.source, state.sort_mode);
    try std.testing.expectEqual(@as(usize, 0), state.sorted_source_indexes.len);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().items.len);
    try std.testing.expectEqualStrings("Root", state.activeList().items[0]);
}

test "search loading clears previous loaded results" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    state.setLoading(std.testing.allocator);

    try std.testing.expect(state.load_state == .loading);
    try std.testing.expectEqual(@as(usize, 0), state.results.len);
    try std.testing.expectEqual(@as(usize, 0), state.labels.len);
    try std.testing.expectEqual(@as(usize, 0), state.list.items.len);
}
