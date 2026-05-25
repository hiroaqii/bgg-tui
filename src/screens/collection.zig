const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const task_bgg = @import("../tasks/bgg.zig");

pub const Result = task_bgg.CollectionResult;
pub const TaskResult = task_bgg.CollectionTaskResult;

pub const status_labels = [_][]const u8{
    "Owned",
    "Prev owned",
    "For trade",
    "Want",
    "Want to play",
    "Want to buy",
    "Wishlist",
    "Preordered",
};

pub const status_clear_index: usize = status_labels.len;

pub fn statusBit(index: usize) u8 {
    return @as(u8, 1) << @intCast(index);
}

pub fn itemMatchesStatusMask(item: bgg_model.CollectionItem, status_mask: u8) bool {
    if (status_mask == 0) return true;
    return ((status_mask & statusBit(0)) != 0 and item.owned) or
        ((status_mask & statusBit(1)) != 0 and item.prev_owned) or
        ((status_mask & statusBit(2)) != 0 and item.for_trade) or
        ((status_mask & statusBit(3)) != 0 and item.want) or
        ((status_mask & statusBit(4)) != 0 and item.want_to_play) or
        ((status_mask & statusBit(5)) != 0 and item.want_to_buy) or
        ((status_mask & statusBit(6)) != 0 and item.wishlist) or
        ((status_mask & statusBit(7)) != 0 and item.preordered);
}

pub fn statusSummary(allocator: std.mem.Allocator, status_mask: u8) ![]const u8 {
    if (status_mask == 0) return try allocator.dupe(u8, "Status: All");

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("Status: ");
    var wrote = false;
    for (status_labels, 0..) |label, index| {
        if ((status_mask & statusBit(index)) == 0) continue;
        if (wrote) try out.writer.writeAll(", ");
        try out.writer.writeAll(label);
        wrote = true;
    }
    return try out.toOwnedSlice();
}

pub const Msg = union(enum) {
    username_input: ui.TextInput.Msg,
    username_paste: []const u8,
    filter_start,
    filter_input: ui.TextInput.Msg,
    filter_paste: []const u8,
    filter_clear,
    change_user,
    refresh,
    status_open,
    status_move_prev,
    status_move_next,
    status_toggle,
    status_close,
    items_loaded: TaskResult,
    list: ui.List.Msg,
};

pub const State = struct {
    username_input: ?ui.TextInput = null,
    filter_input: ?ui.TextInput = null,
    request_id: u64 = 0,
    status_picker: bool = false,
    status_cursor: usize = 0,
    status_mask: u8 = 0,
    load_state: LoadState = .idle,
    // Keep the API result intact so status toggles can filter locally without another request.
    all_items: []bgg_model.CollectionItem = &.{},
    items: []bgg_model.CollectionItem = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,

    pub const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    pub fn initInputs(self: *State, allocator: std.mem.Allocator, default_username: ?[]const u8) !void {
        self.username_input = try ui.TextInput.init(allocator, .{
            .value = default_username orelse "",
            .placeholder = "BGG username",
        });
        errdefer {
            self.username_input.?.deinit();
            self.username_input = null;
        }
        self.filter_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Filter collection",
        });
    }

    pub fn deinitInputs(self: *State) void {
        if (self.username_input) |*input| {
            input.deinit();
            self.username_input = null;
        }
        if (self.filter_input) |*input| {
            input.deinit();
            self.filter_input = null;
        }
    }

    pub fn setLoading(self: *State, allocator: std.mem.Allocator) void {
        self.clearItems(allocator);
        self.load_state = .loading;
    }

    pub fn setFailed(self: *State, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearItems(allocator);
        self.load_state = .{ .failed = message };
    }

    pub fn setLoaded(self: *State, allocator: std.mem.Allocator, items: []bgg_model.CollectionItem, status_mask: u8) !void {
        self.clearItems(allocator);
        self.all_items = items;
        try self.applyStatusFilter(allocator, status_mask);
        self.load_state = .loaded;
    }

    pub fn update(self: *State, msg: ui.List.Msg) void {
        if (self.filter_active) {
            self.filter.update(msg);
        } else {
            self.list.update(msg);
        }
    }

    pub fn handleEvent(self: *const State, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        if (self.filter_active) return self.filter.handleEvent(event);
        if (self.list.items.len == 0) return null;
        return self.list.handleEvent(event);
    }

    pub fn activeList(self: *const State) *const ui.List {
        if (self.filter_active) return &self.filter.list;
        return &self.list;
    }

    pub fn statusFilteredEmpty(self: *const State) bool {
        return self.all_items.len > 0 and self.items.len == 0;
    }

    pub fn sourceIndex(self: *const State, visible_index: usize) ?usize {
        if (self.filter_active) return self.filter.sourceIndex(visible_index);
        if (visible_index >= self.items.len) return null;
        return visible_index;
    }

    pub fn applyFilter(self: *State, allocator: std.mem.Allocator, query: []const u8) !void {
        try self.filter.apply(allocator, self.labels, query);
        self.filter_active = true;
    }

    pub fn applyStatusFilter(self: *State, allocator: std.mem.Allocator, status_mask: u8) !void {
        var projected: std.ArrayList(bgg_model.CollectionItem) = .empty;
        errdefer projected.deinit(allocator);

        for (self.all_items) |item| {
            if (!itemMatchesStatusMask(item, status_mask)) continue;
            try projected.append(allocator, item);
        }

        const next_items = try projected.toOwnedSlice(allocator);
        errdefer allocator.free(next_items);
        const next_labels = try labels_mod.buildCollectionItemLabels(allocator, next_items);
        errdefer labels_mod.freeCollectionItemLabels(allocator, next_labels);

        self.filter.deinit(allocator);
        labels_mod.freeCollectionItemLabels(allocator, self.labels);
        allocator.free(self.items);
        self.items = next_items;
        self.labels = next_labels;
        self.list = ui.List.init(.{ .items = self.labels });
        self.filter_active = false;
    }

    pub fn clearFilter(self: *State, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.clearItems(allocator);
        self.load_state = .idle;
    }

    fn clearItems(self: *State, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        labels_mod.freeCollectionItemLabels(allocator, self.labels);
        allocator.free(self.items);
        bgg_xml.freeCollectionItems(allocator, self.all_items);
        self.labels = &.{};
        self.all_items = &.{};
        self.items = &.{};
        self.list = ui.List.init(.{});
        self.filter_active = false;
    }
};
