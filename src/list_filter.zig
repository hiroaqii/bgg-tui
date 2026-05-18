const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

/// App-local filter state for list screens.
///
/// The state owns the query and the filtered index/label arrays, but borrows
/// the label strings from the source list. Activation can map a visible row
/// back to the original source index with `sourceIndex`.
pub const FilterState = struct {
    query: []u8 = &.{},
    source_indexes: []usize = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),

    pub fn deinit(self: *FilterState, allocator: std.mem.Allocator) void {
        self.clear(allocator);
    }

    pub fn apply(self: *FilterState, allocator: std.mem.Allocator, source_labels: []const []const u8, query: []const u8) !void {
        try self.applyWithSourceIndexes(allocator, source_labels, null, query);
    }

    pub fn applyWithSourceIndexes(
        self: *FilterState,
        allocator: std.mem.Allocator,
        source_labels: []const []const u8,
        source_indexes: ?[]const usize,
        query: []const u8,
    ) !void {
        const next_query = try allocator.dupe(u8, query);
        errdefer allocator.free(next_query);

        var indexes: std.ArrayList(usize) = .empty;
        errdefer indexes.deinit(allocator);
        var labels: std.ArrayList([]const u8) = .empty;
        errdefer labels.deinit(allocator);

        for (source_labels, 0..) |label, index| {
            if (!matchesLabel(label, query)) continue;
            try indexes.append(allocator, if (source_indexes) |map| map[index] else index);
            try labels.append(allocator, label);
        }

        const next_source_indexes = try indexes.toOwnedSlice(allocator);
        errdefer allocator.free(next_source_indexes);
        const next_labels = try labels.toOwnedSlice(allocator);
        errdefer allocator.free(next_labels);

        self.clear(allocator);
        self.query = next_query;
        self.source_indexes = next_source_indexes;
        self.labels = next_labels;
        self.list = ui.List.init(.{ .items = self.labels });
    }

    pub fn sourceIndex(self: *const FilterState, visible_index: usize) ?usize {
        if (visible_index >= self.source_indexes.len) return null;
        return self.source_indexes[visible_index];
    }

    pub fn update(self: *FilterState, msg: ui.List.Msg) void {
        self.list.update(msg);
    }

    pub fn handleEvent(self: *const FilterState, event: chasen.Event) ?ui.List.Msg {
        if (self.labels.len == 0) return null;
        return self.list.handleEvent(event);
    }

    fn clear(self: *FilterState, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        allocator.free(self.source_indexes);
        allocator.free(self.labels);
        self.query = &.{};
        self.source_indexes = &.{};
        self.labels = &.{};
        self.list = ui.List.init(.{});
    }
};

pub fn matchesLabel(label: []const u8, query: []const u8) bool {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed.len == 0) return true;
    return containsAsciiIgnoreCase(label, trimmed);
}

fn containsAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        for (needle, 0..) |needle_byte, i| {
            if (std.ascii.toLower(haystack[start + i]) != std.ascii.toLower(needle_byte)) break;
        } else {
            return true;
        }
    }
    return false;
}

test "filter state keeps all labels for empty query" {
    const labels = [_][]const u8{ "Root", "CATAN", "Azul" };
    var state: FilterState = .{};
    defer state.deinit(std.testing.allocator);

    try state.apply(std.testing.allocator, &labels, "  ");

    try std.testing.expectEqualStrings("  ", state.query);
    try std.testing.expectEqual(@as(usize, 3), state.labels.len);
    try std.testing.expectEqual(@as(usize, 0), state.sourceIndex(0).?);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(2).?);
}

test "filter state matches labels case-insensitively" {
    const labels = [_][]const u8{ "Root", "CATAN", "The Castles of Burgundy" };
    var state: FilterState = .{};
    defer state.deinit(std.testing.allocator);

    try state.apply(std.testing.allocator, &labels, "cat");

    try std.testing.expectEqual(@as(usize, 1), state.labels.len);
    try std.testing.expectEqualStrings("CATAN", state.labels[0]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
}

test "filter state maps visible activation back to source index" {
    const labels = [_][]const u8{ "Root", "Cascadia", "CATAN" };
    var state: FilterState = .{};
    defer state.deinit(std.testing.allocator);

    try state.apply(std.testing.allocator, &labels, "ca");
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 1), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.list.focusedIndex()).?);
}

test "filter state can preserve projected source indexes" {
    const labels = [_][]const u8{ "CATAN", "Cascadia", "Root" };
    const indexes = [_]usize{ 2, 1, 0 };
    var state: FilterState = .{};
    defer state.deinit(std.testing.allocator);

    try state.applyWithSourceIndexes(std.testing.allocator, &labels, &indexes, "ca");
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 1), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(state.list.focusedIndex()).?);
}

test "filter state handles no matches" {
    const labels = [_][]const u8{ "Root", "CATAN" };
    var state: FilterState = .{};
    defer state.deinit(std.testing.allocator);

    try state.apply(std.testing.allocator, &labels, "zz");

    try std.testing.expectEqual(@as(usize, 0), state.labels.len);
    try std.testing.expectEqual(@as(?usize, null), state.sourceIndex(0));
    try std.testing.expectEqual(@as(?ui.List.Msg, null), state.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }));
}

test "matches label trims query before matching" {
    try std.testing.expect(matchesLabel("Terraforming Mars", " mars "));
    try std.testing.expect(!matchesLabel("Terraforming Mars", "venus"));
}
