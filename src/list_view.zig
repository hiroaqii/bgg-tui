const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        return self.end - self.start;
    }
};

pub const Density = enum {
    compact,
    normal,
    comfortable,
    relaxed,

    pub fn fromConfig(value: []const u8) Density {
        if (std.mem.eql(u8, value, "compact")) return .compact;
        if (std.mem.eql(u8, value, "comfortable")) return .comfortable;
        if (std.mem.eql(u8, value, "relaxed")) return .relaxed;
        return .normal;
    }

    /// Number of terminal rows consumed by one rendered item.
    ///
    /// Keep every density at one row for now. This preserves the Go version's
    /// visible item count while connecting the compatibility config key.
    /// Future metadata-rich items can let density change how much information
    /// each row shows instead of reducing the number of visible items.
    pub fn rowStride(self: Density) u16 {
        _ = self;
        return 1;
    }
};

/// Return the visible item range needed to keep `focused_index` on screen.
///
/// This helper is intentionally stateless. App state still owns the full list
/// focus; rendering computes the slice needed for the current surface height.
pub fn visibleRange(item_count: usize, focused_index: usize, visible_height: usize) Range {
    if (item_count == 0 or visible_height == 0) return .{ .start = 0, .end = 0 };

    const clamped_height = @min(visible_height, item_count);
    const start = ui.Viewport.offsetKeepingIndexVisible(item_count, clamped_height, 0, focused_index);
    const range = ui.Viewport.init(.{
        .total = item_count,
        .height = clamped_height,
        .offset = start,
    }).visibleRange();

    return .{ .start = range.start, .end = range.end };
}

pub fn viewList(list: *const ui.List, surface: *chasen.Surface, opts: ui.List.ViewOptions) void {
    viewListWithDensity(list, surface, opts, .normal);
}

pub fn viewListWithDensity(list: *const ui.List, surface: *chasen.Surface, opts: ui.List.ViewOptions, density: Density) void {
    const height = surface.size().height;
    if (height == 0 or list.items.len == 0) return;

    const visible_capacity = visibleItemCapacity(height, density);
    const range = visibleRange(list.items.len, list.focusedIndex(), visible_capacity);
    if (range.len() == 0) return;

    const width = surface.size().width;
    const stride = density.rowStride();
    const focused_index = list.focusedIndex();
    for (list.items[range.start..range.end], 0..) |item, local_index| {
        const global_index = range.start + local_index;
        const row: u16 = @intCast(local_index * stride);
        if (row >= height) break;

        const focused = global_index == focused_index;
        const selected = opts.selected_index != null and opts.selected_index.? == global_index;
        const marker = if (focused) opts.focused_marker else opts.marker;

        _ = surface.borrowTextAt(0, row, marker, opts.marker_style);
        if (width > 2) {
            _ = surface.borrowTextAt(2, row, item, itemStyle(opts, focused, selected));
        }
    }

    if (opts.show_cursor and focused_index >= range.start and focused_index < range.end) {
        const cursor_row: u16 = @intCast((focused_index - range.start) * stride);
        if (cursor_row < height) surface.showCursor(@min(@as(u16, 2), width - 1), cursor_row);
    }
}

pub fn visibleItemCapacity(visible_height: usize, density: Density) usize {
    if (visible_height == 0) return 0;
    const stride: usize = density.rowStride();
    return (visible_height + stride - 1) / stride;
}

pub fn positionText(allocator: std.mem.Allocator, range: Range, item_count: usize) ![]u8 {
    if (item_count == 0 or range.len() == 0) return try std.fmt.allocPrint(allocator, "0/{d}", .{item_count});
    return try std.fmt.allocPrint(allocator, "{d}-{d}/{d}", .{ range.start + 1, range.end, item_count });
}

pub fn focusedPositionText(allocator: std.mem.Allocator, focused_index: usize, item_count: usize) ![]u8 {
    if (item_count == 0) return try std.fmt.allocPrint(allocator, "0/0", .{});
    return try std.fmt.allocPrint(allocator, "{d}/{d}", .{ @min(focused_index, item_count - 1) + 1, item_count });
}

fn itemStyle(opts: ui.List.ViewOptions, focused: bool, selected: bool) chasen.TextStyle {
    if (focused and selected) return opts.focused_selected_style;
    if (focused) return opts.focused_style;
    if (selected) return opts.selected_style;
    return opts.item_style;
}

test "visible range keeps focused item in view" {
    try std.testing.expectEqual(Range{ .start = 0, .end = 0 }, visibleRange(0, 0, 5));
    try std.testing.expectEqual(Range{ .start = 0, .end = 0 }, visibleRange(10, 0, 0));
    try std.testing.expectEqual(Range{ .start = 0, .end = 3 }, visibleRange(3, 0, 10));
    try std.testing.expectEqual(Range{ .start = 0, .end = 5 }, visibleRange(10, 0, 5));
    try std.testing.expectEqual(Range{ .start = 1, .end = 6 }, visibleRange(10, 5, 5));
    try std.testing.expectEqual(Range{ .start = 5, .end = 10 }, visibleRange(10, 99, 5));
}

test "position text uses one-based visible range" {
    const text = try positionText(std.testing.allocator, .{ .start = 5, .end = 10 }, 20);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("6-10/20", text);
}

test "position text handles empty visible range" {
    const text = try positionText(std.testing.allocator, .{ .start = 0, .end = 0 }, 20);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("0/20", text);
}

test "focused position text uses one-based focused index" {
    const text = try focusedPositionText(std.testing.allocator, 2, 50);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("3/50", text);
}

test "focused position text handles empty and out-of-range focus" {
    const empty = try focusedPositionText(std.testing.allocator, 0, 0);
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("0/0", empty);

    const clamped = try focusedPositionText(std.testing.allocator, 99, 3);
    defer std.testing.allocator.free(clamped);
    try std.testing.expectEqualStrings("3/3", clamped);
}

test "density parses config values" {
    try std.testing.expectEqual(Density.compact, Density.fromConfig("compact"));
    try std.testing.expectEqual(Density.normal, Density.fromConfig("normal"));
    try std.testing.expectEqual(Density.comfortable, Density.fromConfig("comfortable"));
    try std.testing.expectEqual(Density.relaxed, Density.fromConfig("relaxed"));
    try std.testing.expectEqual(Density.normal, Density.fromConfig("unknown"));
}

test "visible item capacity preserves list count across density settings" {
    try std.testing.expectEqual(@as(usize, 0), visibleItemCapacity(0, .normal));
    try std.testing.expectEqual(@as(usize, 5), visibleItemCapacity(5, .normal));
    try std.testing.expectEqual(@as(usize, 5), visibleItemCapacity(5, .comfortable));
    try std.testing.expectEqual(@as(usize, 5), visibleItemCapacity(5, .relaxed));
}

test "density list preserves one-row rendering" {
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma" };
    var list = ui.List.init(.{ .items = &items });
    list.update(.move_next);

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(12, 5);
    defer ts.deinit();

    viewListWithDensity(&list, &ts.surface, .{}, .comfortable);

    try ts.expectCellText(0, 0, " ");
    try ts.expectCellText(2, 0, "A");
    try ts.expectCellText(0, 1, ">");
    try ts.expectCellText(2, 1, "B");
    try ts.expectCellText(2, 2, "G");
}
