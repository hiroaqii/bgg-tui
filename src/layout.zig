const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const config_mod = @import("config.zig");
const screens = @import("screens/root.zig");

pub const list_screen_min_stats_width: u16 = 96;
pub const list_screen_max_height: u16 = 34;
pub const forum_screen_max_size = chasen.Size{ .width = 88, .height = 34 };
pub const detail_image_panel_width: u16 = 28;
pub const detail_image_panel_gap: u16 = 2;
pub const list_image_panel_gap: u16 = 2;
pub const list_image_panel_width: u16 = 20;
pub const list_image_min_text_width: u16 = 72;

const detail_outer_reserved_rows: u16 = 3;
const detail_image_panel_height: u16 = 14;
const detail_image_min_text_width: u16 = 56;
const list_image_panel_height: u16 = 10;
const thread_outer_reserved_rows: u16 = 3;

// App screens receive a local surface. `ui.layout.center` handles clamping when
// the terminal is smaller than the requested block.
pub fn centeredSurface(surface: *chasen.Surface, size: chasen.Size) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), size));
}

pub fn detailSurface(surface: *chasen.Surface, configured_width: u16) chasen.Surface {
    // Detail is long-form content, so it uses the available body height while
    // still constraining width through the user's display setting.
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = configured_width,
        .height = surface.size().height,
    }));
}

pub fn detailWantsImagePanel(config: config_mod.Config) bool {
    return config.display.show_images and config.display.image_protocol != .off;
}

pub fn detailSurfaceSizeForTerminal(config: config_mod.Config, terminal_size: chasen.Size) chasen.Size {
    const body_size = screenBodySizeForTerminal(terminal_size);
    return .{
        .width = @min(config.display.detail_width, body_size.width),
        .height = body_size.height,
    };
}

pub fn detailContentWidthForSize(config: config_mod.Config, size: chasen.Size, density: []const u8) usize {
    const layout_value = detailLayout(size.height, density);
    if (detailImagePanelRectForSize(config, size, layout_value)) |rect|
        return rect.col -| detail_image_panel_gap;
    return size.width;
}

pub fn detailImagePanelRectForSize(config: config_mod.Config, size: chasen.Size, detail_layout: screens.detail.Layout) ?chasen.Rect {
    if (!detailWantsImagePanel(config)) return null;

    if (size.width < detail_image_min_text_width + detail_image_panel_gap + detail_image_panel_width)
        return null;
    if (size.height <= detail_layout.content_row + 6) return null;

    const available_height = size.height - detail_layout.content_row - 2;
    return .{
        .col = size.width - detail_image_panel_width,
        .row = detail_layout.content_row,
        .width = detail_image_panel_width,
        .height = @min(detail_image_panel_height, available_height),
    };
}

pub fn listImagePanelRectForSize(config: config_mod.Config, size: chasen.Size, body_row: u16, bottom_limit: ?u16) ?chasen.Rect {
    if (!detailWantsImagePanel(config)) return null;
    if (size.width < list_image_min_text_width + list_image_panel_gap + list_image_panel_width)
        return null;
    if (size.height <= body_row + 6) return null;

    const panel_bottom = bottom_limit orelse size.height -| 1;
    if (panel_bottom <= body_row + 5) return null;
    const available_height = panel_bottom - body_row - 1;
    return .{
        .col = size.width - list_image_panel_width,
        .row = body_row,
        .width = list_image_panel_width,
        .height = @min(list_image_panel_height, available_height),
    };
}

pub fn listSurface(surface: *chasen.Surface, configured_width: u16) chasen.Surface {
    // Hot Games and Collection have stat legends/columns. Keep a practical
    // minimum width so those columns are visible, while still allowing users to
    // expand wider through the list width setting.
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = @max(configured_width, list_screen_min_stats_width),
        .height = list_screen_max_height,
    }));
}

pub fn forumSurface(surface: *chasen.Surface) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), forum_screen_max_size));
}

pub fn forumListSurface(surface: *chasen.Surface, item_count: usize, list_body_row: u16) chasen.Surface {
    const count: u16 = @intCast(@min(item_count, std.math.maxInt(u16)));
    const height = @min(forum_screen_max_size.height, @max(@as(u16, 7), list_body_row + count + 2));
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = forum_screen_max_size.width,
        .height = height,
    }));
}

pub fn threadSurface(surface: *chasen.Surface, configured_width: u16) chasen.Surface {
    // Threads are long-form content like Detail, so height follows the available
    // body while width remains user-configurable.
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = configured_width,
        .height = surface.size().height,
    }));
}

pub fn threadLayout(area_height: u16, density: []const u8) screens.thread.Layout {
    return screens.thread.layout(area_height, density, .{ .outer_reserved_rows = thread_outer_reserved_rows });
}

pub fn detailLayout(area_height: u16, density: []const u8) screens.detail.Layout {
    // The Go version computed detail density from full terminal height. Chasen
    // renders inside a panel plus global status row, so compensate for that
    // outer chrome while keeping Detail's child surface as the drawing boundary.
    return screens.detail.layout(area_height, density, .{ .outer_reserved_rows = detail_outer_reserved_rows });
}

pub fn screenBodySizeForTerminal(terminal_size: chasen.Size) chasen.Size {
    const shell_rect = chasen.Rect{
        .col = 0,
        .row = 0,
        .width = terminal_size.width,
        .height = terminal_size.height -| 1,
    };
    const body_rect = ui.Panel.contentRectFor(shell_rect, .all(1));
    return .{
        .width = body_rect.width,
        .height = @max(@as(u16, 1), body_rect.height),
    };
}

pub fn surfaceRect(surface: *const chasen.Surface) chasen.Rect {
    const size = surface.size();
    return .{ .col = 0, .row = 0, .width = size.width, .height = size.height };
}

test "surfaceRect creates a root-relative rectangle" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(80, 24);
    defer ts.deinit();

    try std.testing.expectEqual(chasen.Rect{
        .col = 0,
        .row = 0,
        .width = 80,
        .height = 24,
    }, surfaceRect(&ts.surface));
}

test "list surface keeps stats columns visible" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(120, 40);
    defer ts.deinit();

    const area = listSurface(&ts.surface, 40);

    try std.testing.expectEqual(list_screen_min_stats_width, area.size().width);
    try std.testing.expectEqual(list_screen_max_height, area.size().height);
}

test "list surface can expand beyond stats minimum" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(140, 40);
    defer ts.deinit();

    const area = listSurface(&ts.surface, 120);

    try std.testing.expectEqual(@as(u16, 120), area.size().width);
    try std.testing.expectEqual(list_screen_max_height, area.size().height);
}

test "list surface shrinks for small terminals" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(40, 12);
    defer ts.deinit();

    const area = listSurface(&ts.surface, 40);

    try std.testing.expectEqual(@as(u16, 40), area.size().width);
    try std.testing.expectEqual(@as(u16, 12), area.size().height);
}

test "centered surface shrinks for narrow terminals" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(36, 10);
    defer ts.deinit();

    const area = centeredSurface(&ts.surface, .{ .width = 72, .height = 27 });

    try std.testing.expectEqual(@as(u16, 36), area.size().width);
    try std.testing.expectEqual(@as(u16, 10), area.size().height);
}

test "detail surface clamps configured width to available width" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(50, 16);
    defer ts.deinit();

    const area = detailSurface(&ts.surface, 120);

    try std.testing.expectEqual(@as(u16, 50), area.size().width);
    try std.testing.expectEqual(@as(u16, 16), area.size().height);
}

test "detail content width reserves room for image panel when enabled" {
    const full_size = chasen.Size{ .width = 120, .height = 24 };
    const narrow_size = chasen.Size{ .width = 80, .height = 24 };

    try std.testing.expectEqual(@as(usize, 120), detailContentWidthForSize(.{
        .display = .{ .detail_width = 120, .show_images = false },
    }, full_size, "normal"));
    try std.testing.expectEqual(@as(usize, 120), detailContentWidthForSize(.{
        .display = .{ .detail_width = 120, .image_protocol = .off },
    }, full_size, "normal"));
    try std.testing.expectEqual(@as(usize, 90), detailContentWidthForSize(.{
        .display = .{ .detail_width = 120, .show_images = true, .image_protocol = .auto },
    }, full_size, "normal"));
    try std.testing.expectEqual(@as(usize, 80), detailContentWidthForSize(.{
        .display = .{ .detail_width = 80, .show_images = true, .image_protocol = .auto },
    }, narrow_size, "normal"));
}

test "detail image panel requires enough width and enabled images" {
    const layout_value = detailLayout(24, "normal");
    const config = config_mod.Config{
        .api = .{ .token = "token" },
        .display = .{ .show_images = true, .image_protocol = .auto },
    };

    const rect = detailImagePanelRectForSize(config, .{ .width = 120, .height = 24 }, layout_value).?;
    try std.testing.expectEqual(@as(u16, 92), rect.col);
    try std.testing.expectEqual(@as(u16, detail_image_panel_width), rect.width);

    const disabled = config_mod.Config{
        .api = .{ .token = "token" },
        .display = .{ .show_images = true, .image_protocol = .off },
    };
    try std.testing.expect(detailImagePanelRectForSize(disabled, .{ .width = 120, .height = 24 }, layout_value) == null);
}
