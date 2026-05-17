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

/// Return the visible item range needed to keep `focused_index` on screen.
///
/// This helper is intentionally stateless. App state still owns the full list
/// focus; rendering computes the slice needed for the current surface height.
pub fn visibleRange(item_count: usize, focused_index: usize, visible_height: usize) Range {
    if (item_count == 0 or visible_height == 0) return .{ .start = 0, .end = 0 };

    const clamped_focus = @min(focused_index, item_count - 1);
    const clamped_height = @min(visible_height, item_count);
    const start = if (clamped_focus < clamped_height) 0 else clamped_focus - clamped_height + 1;
    return .{
        .start = start,
        .end = @min(item_count, start + clamped_height),
    };
}

pub fn viewList(list: *const ui.List, surface: *chasen.Surface, opts: ui.List.ViewOptions) void {
    const height = surface.size().height;
    if (height == 0 or list.items.len == 0) return;

    const range = visibleRange(list.items.len, list.focusedIndex(), height);
    if (range.len() == 0) return;

    var visible = ui.List.init(.{ .items = list.items[range.start..range.end] });
    visible.focus.index = list.focusedIndex() - range.start;

    var visible_opts = opts;
    if (opts.selected_index) |selected_index| {
        visible_opts.selected_index = if (selected_index >= range.start and selected_index < range.end)
            selected_index - range.start
        else
            null;
    }

    visible.view(surface, visible_opts);
}

pub fn positionText(allocator: std.mem.Allocator, range: Range, item_count: usize) ![]u8 {
    if (item_count == 0 or range.len() == 0) return try std.fmt.allocPrint(allocator, "0/{d}", .{item_count});
    return try std.fmt.allocPrint(allocator, "{d}-{d}/{d}", .{ range.start + 1, range.end, item_count });
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
