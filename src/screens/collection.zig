const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const labels_mod = @import("../labels.zig");
const list_filter = @import("../list_filter.zig");
const task_bgg = @import("../tasks/bgg.zig");

const filter_row: u16 = 4;
const username_row: u16 = 2;

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

pub const EventAction = union(enum) {
    msg: Msg,
    main_menu,
    quit,
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

    pub fn handleScreenEvent(self: *const State, event: chasen.Event) ?EventAction {
        if (self.status_picker) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{})) return .{ .msg = .status_close };
                    if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .{ .msg = .status_move_prev };
                    if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .{ .msg = .status_move_next };
                    if (key.matches(chasen.Key.enter, .{})) return .{ .msg = .status_toggle };
                },
                else => {},
            }
            return null;
        }

        if (self.filter_active) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{})) return .{ .msg = .filter_clear };
                    if (key.matches(chasen.Key.enter, .{})) {
                        if (self.handleEvent(event)) |msg| return .{ .msg = .{ .list = msg } };
                        return null;
                    }
                },
                .paste => |text| return .{ .msg = .{ .filter_paste = text } },
                else => {},
            }
            if (self.filter_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .msg = .{ .filter_input = msg } };
            }
            if (self.handleEvent(event)) |msg| return .{ .msg = .{ .list = msg } };
            return null;
        }

        switch (event) {
            .key_press => |key| {
                if (self.load_state == .loaded) {
                    if (key.codepoint == 's') return .{ .msg = .status_open };
                    if (key.codepoint == '/') return .{ .msg = .filter_start };
                    if (key.codepoint == 'u') return .{ .msg = .change_user };
                    if (key.codepoint == 'r') return .{ .msg = .refresh };
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'm') return .main_menu;
                    if (key.codepoint == 'q') return .quit;
                } else if (key.matches(chasen.Key.escape, .{})) {
                    return .main_menu;
                }
            },
            .paste => |text| if (self.load_state != .loaded) return .{ .msg = .{ .username_paste = text } },
            else => {},
        }

        if (self.load_state == .loaded) {
            if (self.handleEvent(event)) |msg| return .{ .msg = .{ .list = msg } };
        } else if (self.username_input) |*input| {
            if (input.handleEvent(event)) |msg| return .{ .msg = .{ .username_input = msg } };
        }
        return null;
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

    pub fn drawUsernameInput(self: *const State, surface: *chasen.Surface, style: chasen.TextStyle) void {
        _ = surface.borrowTextAt(0, username_row, "User:", style);
        if (self.username_input) |*input| {
            var input_area = surface.child(.{
                .col = 6,
                .row = username_row,
                .width = surface.size().width -| 6,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
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

test "collection status mask filters matching items" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, statusBit(0) | statusBit(6));
    defer state.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), state.items.len);
    try state.applyStatusFilter(std.testing.allocator, statusBit(6));
    try std.testing.expectEqual(@as(usize, 2), state.items.len);
    try std.testing.expectEqual(@as(u32, 2), state.items[0].id);
    try std.testing.expectEqual(@as(u32, 3), state.items[1].id);
    try state.applyStatusFilter(std.testing.allocator, 0);
    try std.testing.expectEqual(@as(usize, 3), state.items.len);
}

test "collection status filter distinguishes filtered empty from API empty" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, statusBit(6));
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.statusFilteredEmpty());
    try state.applyStatusFilter(std.testing.allocator, 0);
    try std.testing.expect(!state.statusFilteredEmpty());
}

test "collection filter maps visible activation back to source item" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, 0);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "collection status and name filters activate projected item" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN"), .wishlist = true };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, statusBit(6));
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    const projected_index = state.sourceIndex(state.activeList().focusedIndex()).?;
    try std.testing.expectEqual(@as(u32, 3), state.items[projected_index].id);
}

test "collection focus resets and clamps after status projection" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, statusBit(6));
    defer state.deinit(std.testing.allocator);

    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());

    try state.applyStatusFilter(std.testing.allocator, statusBit(0));
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(u32, 1), state.items[state.sourceIndex(0).?].id);
}

test "collection screen event routes loaded list activation and shortcuts" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN"), .owned = true };

    var state: State = .{};
    try state.setLoaded(std.testing.allocator, items, 0);
    defer state.deinit(std.testing.allocator);

    const activate = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?;
    try std.testing.expect(activate == .msg);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 0 }, activate.msg.list);

    const filter = state.handleScreenEvent(.{ .key_press = .{ .codepoint = '/' } }).?;
    try std.testing.expect(filter == .msg);
    try std.testing.expect(filter.msg == .filter_start);

    const status = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 's' } }).?;
    try std.testing.expect(status == .msg);
    try std.testing.expect(status.msg == .status_open);

    const change_user = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'u' } }).?;
    try std.testing.expect(change_user == .msg);
    try std.testing.expect(change_user.msg == .change_user);

    const refresh = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'r' } }).?;
    try std.testing.expect(refresh == .msg);
    try std.testing.expect(refresh.msg == .refresh);
}

test "collection screen event routes status picker controls" {
    var state: State = .{ .status_picker = true };

    const prev = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'k' } }).?;
    try std.testing.expect(prev == .msg);
    try std.testing.expect(prev.msg == .status_move_prev);

    const next = state.handleScreenEvent(.{ .key_press = .{ .codepoint = 'j' } }).?;
    try std.testing.expect(next == .msg);
    try std.testing.expect(next.msg == .status_move_next);

    const toggle = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?;
    try std.testing.expect(toggle == .msg);
    try std.testing.expect(toggle.msg == .status_toggle);

    const close = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(close == .msg);
    try std.testing.expect(close.msg == .status_close);
}

test "collection screen event routes active filter input" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: State = .{};
    state.filter_input = try ui.TextInput.init(std.testing.allocator, .{});
    try state.setLoaded(std.testing.allocator, items, 0);
    try state.applyFilter(std.testing.allocator, "");
    defer {
        state.deinitInputs();
        state.deinit(std.testing.allocator);
    }

    const paste_action = state.handleScreenEvent(.{ .paste = "cat" }).?;
    try std.testing.expect(paste_action == .msg);
    try std.testing.expect(paste_action.msg == .filter_paste);
    try std.testing.expectEqualStrings("cat", paste_action.msg.filter_paste);

    const clear = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(clear == .msg);
    try std.testing.expect(clear.msg == .filter_clear);
}

test "collection screen event routes username input and navigation" {
    var state: State = .{};
    state.username_input = try ui.TextInput.init(std.testing.allocator, .{});
    defer state.deinitInputs();

    const paste_action = state.handleScreenEvent(.{ .paste = "hiro" }).?;
    try std.testing.expect(paste_action == .msg);
    try std.testing.expect(paste_action.msg == .username_paste);
    try std.testing.expectEqualStrings("hiro", paste_action.msg.username_paste);

    const exit = state.handleScreenEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(exit == .main_menu);
}
