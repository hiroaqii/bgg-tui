const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const list_view = @import("../list_view.zig");
const list_sort = @import("../list_sort.zig");
const motion = @import("../motion.zig");
const paste = @import("../paste.zig");
const task_bgg = @import("../tasks/bgg.zig");

const filter_row: u16 = 4;
const position_row: u16 = 2;
const body_row: u16 = 4;
const filtered_body_row: u16 = 6;
const footer_gap: u16 = 1;

pub const Result = task_bgg.SearchResult;
pub const TaskResult = task_bgg.SearchTaskResult;

pub const InputViewOptions = struct {
    title_style: chasen.TextStyle,
    muted_title_style: chasen.TextStyle,
    muted_style: chasen.TextStyle,
    subtle_style: chasen.TextStyle,
    footer_hint: []const u8,
    loading_scan_frame: u64,
};

pub const ResultsViewOptions = struct {
    title_style: chasen.TextStyle,
    focused_style: chasen.TextStyle,
    muted_style: chasen.TextStyle,
    subtle_style: chasen.TextStyle,
    footer_hint: []const u8,
    list_density: list_view.Density,
    selection: []const u8,
    animation_frame: u64,
    loading_scan_frame: u64,
};

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

pub const EventAction = union(enum) {
    msg: Msg,
    main_menu,
    search_input,
    quit,
};

pub const Action = union(enum) {
    none,
    start_search,
    open_result: usize,
    loaded: TaskResult,
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

    pub fn handleInputScreenEvent(self: *const State, event: chasen.Event) ?EventAction {
        switch (event) {
            .key_press => |key| if (key.matches(chasen.Key.escape, .{})) return .main_menu,
            .paste => |text| return .{ .msg = .{ .paste = text } },
            else => {},
        }
        if (self.input) |*input| {
            if (input.handleEvent(event)) |msg| return .{ .msg = .{ .input = msg } };
        }
        return null;
    }

    pub fn handleResultsScreenEvent(self: *const State, event: chasen.Event) ?EventAction {
        switch (event) {
            .key_press => |key| {
                if (self.filter_active) {
                    if (key.matches(chasen.Key.escape, .{})) return .{ .msg = .filter_clear };
                    if (key.codepoint == 'b') return .search_input;
                    if (key.matches(chasen.Key.enter, .{})) {
                        if (self.handleEvent(event)) |msg| return .{ .msg = .{ .list = msg } };
                        return null;
                    }
                } else if (key.codepoint == '/') {
                    return .{ .msg = .filter_start };
                } else {
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .search_input;
                    if (key.codepoint == 'm') return .main_menu;
                    if (key.codepoint == 's') return .{ .msg = .sort_toggle };
                    if (key.codepoint == 'q') return .quit;
                }
            },
            .paste => |text| if (self.filter_active) return .{ .msg = .{ .filter_paste = text } },
            else => {},
        }

        if (self.filter_active) {
            if (self.filter_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .msg = .{ .filter_input = msg } };
            }
        }
        if (self.handleEvent(event)) |msg| return .{ .msg = .{ .list = msg } };
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

    pub fn updateScreen(self: *State, allocator: std.mem.Allocator, msg: Msg) !Action {
        switch (msg) {
            .input => |input_msg| {
                if (input_msg == .submit) return .start_search;
                if (self.input) |*input| try input.update(input_msg);
                return .none;
            },
            .paste => |text| {
                if (self.input) |*input| try paste.insertCodepoints(input, text);
                return .none;
            },
            .filter_start => {
                try self.startFilter(allocator);
                return .none;
            },
            .filter_input => |input_msg| {
                if (input_msg == .submit) return .none;
                if (self.filter_input) |*input| try input.update(input_msg);
                try self.applyFilterFromInput(allocator);
                return .none;
            },
            .filter_paste => |text| {
                if (self.filter_input) |*input| {
                    try paste.insertCodepoints(input, text);
                    try self.applyFilterFromInput(allocator);
                }
                return .none;
            },
            .filter_clear => {
                try self.clearFilterInput(allocator);
                return .none;
            },
            .sort_toggle => {
                try self.toggleSort(allocator);
                return .none;
            },
            .results_loaded => |result| return .{ .loaded = result },
            .list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => {
                    self.update(list_msg);
                    return .none;
                },
                .activate => |index| {
                    if (self.sourceIndex(index)) |source_index| return .{ .open_result = source_index };
                    return .none;
                },
            },
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

    pub fn drawFilterInput(self: *const State, surface: *chasen.Surface, row: u16, style: chasen.TextStyle) void {
        _ = surface.borrowTextAt(0, row, "Filter:", style);
        if (self.filter_input) |*input| {
            var input_area = surface.child(.{
                .col = 8,
                .row = row,
                .width = surface.size().width -| 8,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    pub fn viewInput(self: *const State, area: *chasen.Surface, opts: InputViewOptions) void {
        _ = area.borrowTextAt(0, 0, "Search Games", opts.title_style);

        if (self.input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 2, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        switch (self.load_state) {
            .idle => drawGuidance(area, 4, "Search board games", "Enter at least 3 characters and press Enter.", opts.muted_title_style, opts.muted_style),
            .loading => drawLoadingGuidance(area, 4, "Search board games", "Search request is running...", opts.muted_title_style, opts.muted_style, opts.loading_scan_frame),
            .failed => |message| drawGuidance(area, 4, "Could not search games.", message, opts.muted_title_style, opts.muted_style),
            .loaded => drawGuidance(area, 4, "Search complete", "Press Enter to run a new search.", opts.muted_title_style, opts.muted_style),
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, opts.footer_hint, opts.subtle_style);
    }

    pub fn viewResults(self: *const State, area: *chasen.Surface, opts: ResultsViewOptions) !void {
        _ = try area.printAt(0, 0, opts.title_style, "Search Results ({s})", .{self.sort_mode.label(.search_results)});

        switch (self.load_state) {
            .idle => drawCenteredGuidance(area, "No search yet", "Run a search to see matching board games."),
            .loading => drawCenteredLoadingGuidance(area, "Search Results", "Searching BoardGameGeek...", opts.muted_style, opts.loading_scan_frame),
            .failed => |message| drawCenteredGuidance(area, "Could not search games.", message),
            .loaded => {
                if (self.list.items.len == 0) {
                    drawCenteredGuidance(area, "No results", "No games matched the current query.");
                } else if (self.filter_active and self.filter.labels.len == 0) {
                    self.drawFilterInput(area, filter_row, opts.subtle_style);
                    drawCenteredGuidanceKeepingCursor(area, "No matches", "No search results match the filter.");
                } else {
                    const current_body_row = if (self.filter_active) filtered_body_row else body_row;
                    if (self.filter_active) self.drawFilterInput(area, filter_row, opts.subtle_style);
                    const list = self.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = current_body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (current_body_row + 1 + footer_gap),
                    });
                    list_view.viewListWithDensitySelection(list, &list_area, .{
                        .focused_style = opts.focused_style,
                        .show_cursor = false,
                    }, opts.list_density, opts.selection, opts.animation_frame);
                    try drawListPosition(area, list, opts.subtle_style);
                    drawSortMode(area, self.sort_mode.label(.search_results), opts.subtle_style);
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, opts.footer_hint, opts.subtle_style);
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

fn drawGuidance(surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8, title_style: chasen.TextStyle, message_style: chasen.TextStyle) void {
    _ = surface.borrowTextAt(0, row, title, title_style);
    _ = surface.borrowTextAt(0, row + 1, message, message_style);
}

fn drawLoadingGuidance(surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8, title_style: chasen.TextStyle, message_style: chasen.TextStyle, frame: u64) void {
    _ = surface.borrowTextAt(0, row, title, title_style);
    motion.drawStatusScanText(surface, 0, row + 1, message, message_style, frame);
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

fn drawListPosition(surface: *chasen.Surface, list: *const ui.List, style: chasen.TextStyle) !void {
    const item_count = list.items.len;
    if (item_count == 0 or surface.size().height < 2) return;

    const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
    _ = surface.borrowTextAt(0, position_row, text, style);
}

fn drawSortMode(surface: *chasen.Surface, label: []const u8, style: chasen.TextStyle) void {
    if (surface.size().width <= 12 or surface.size().height <= position_row) return;
    _ = surface.borrowTextAt(10, position_row, label, style);
}

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

test "search input screen event maps input and exit actions" {
    var state: State = .{};
    state.input = try ui.TextInput.init(std.testing.allocator, .{});
    defer state.deinitInputs();

    const paste_action = state.handleInputScreenEvent(.{ .paste = "root" }).?;
    try std.testing.expect(paste_action == .msg);
    try std.testing.expect(paste_action.msg == .paste);
    try std.testing.expectEqualStrings("root", paste_action.msg.paste);

    const exit = state.handleInputScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(exit == .main_menu);
}

test "search results screen event maps filter and navigation actions" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    var state: State = .{};
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    try state.setLoaded(std.testing.allocator, results);
    defer {
        state.deinitInputs();
        state.deinit(std.testing.allocator);
    }

    const filter = state.handleResultsScreenEvent(.{ .key_press = .{ .codepoint = '/' } }).?;
    try std.testing.expect(filter == .msg);
    try std.testing.expect(filter.msg == .filter_start);

    const back = state.handleResultsScreenEvent(.{ .key_press = .{ .codepoint = 'b' } }).?;
    try std.testing.expect(back == .search_input);

    try state.applyFilter(std.testing.allocator, "");
    const paste_action = state.handleResultsScreenEvent(.{ .paste = "ca" }).?;
    try std.testing.expect(paste_action == .msg);
    try std.testing.expect(paste_action.msg == .filter_paste);
    try std.testing.expectEqualStrings("ca", paste_action.msg.filter_paste);

    const clear = state.handleResultsScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(clear == .msg);
    try std.testing.expect(clear.msg == .filter_clear);
}
