const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const list_view = @import("list_view.zig");
const motion = @import("motion.zig");

pub const RowBuilder = *const fn (
    context: *const anyopaque,
    allocator: std.mem.Allocator,
    visible_index: usize,
) anyerror!ui.ColumnList.Row;

pub const ViewOptions = struct {
    focused_style: chasen.TextStyle,
    selection: []const u8,
    animation_frame: u64,
    column_gap: u16 = 2,
    show_cursor: bool = false,
};

const FocusedTextContext = struct {
    selection: []const u8,
    animation_frame: u64,
};

/// Draw the visible slice of an app-owned list as a `ColumnList`.
///
/// The app still owns filtering, sorting, activation, and source-index mapping.
/// This helper only centralizes the repeated viewport/focus wiring needed when
/// a bgg-tui screen uses `ColumnList` for row rendering.
pub fn viewVisibleRows(
    list: *const ui.List,
    surface: *chasen.Surface,
    columns: []const ui.ColumnList.Column,
    builder_context: *const anyopaque,
    build_row: RowBuilder,
    opts: ViewOptions,
) !void {
    const range = list_view.visibleRange(list.items.len, list.focusedIndex(), surface.size().height);
    const rows = try buildRows(surface.frameAllocator(), range, builder_context, build_row);

    var column_list = ui.ColumnList.init(.{
        .columns = columns,
        .rows = rows,
    });
    if (list.focusedIndex() >= range.start and list.focusedIndex() < range.end) {
        column_list.focus.index = list.focusedIndex() - range.start;
    }

    const focused_text_context: FocusedTextContext = .{
        .selection = opts.selection,
        .animation_frame = opts.animation_frame,
    };
    column_list.view(surface, .{
        .focused_style = opts.focused_style,
        .column_gap = opts.column_gap,
        .focused_text_drawer = drawFocusedText,
        .focused_text_drawer_context = &focused_text_context,
        .show_cursor = opts.show_cursor,
    });
}

fn buildRows(
    allocator: std.mem.Allocator,
    range: list_view.Range,
    builder_context: *const anyopaque,
    build_row: RowBuilder,
) ![]ui.ColumnList.Row {
    const visible_count = range.end - range.start;
    const rows = try allocator.alloc(ui.ColumnList.Row, visible_count);
    for (rows, 0..) |*row, local_index| {
        row.* = try build_row(builder_context, allocator, range.start + local_index);
    }
    return rows;
}

fn drawFocusedText(
    surface: *chasen.Surface,
    col: u16,
    row: u16,
    text: []const u8,
    style: chasen.TextStyle,
    context: ?*const anyopaque,
) void {
    const focused_context: *const FocusedTextContext = @ptrCast(@alignCast(context.?));
    motion.drawFocusedText(surface, col, row, text, style, focused_context.selection, focused_context.animation_frame);
}
