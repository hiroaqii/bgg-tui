const chasen = @import("chasen");
const ui = @import("chasen_ui");
const std = @import("std");

const style_mod = @import("style.zig");

pub const Options = struct {
    version: []const u8,
    border: ui.Panel.Border = .ascii,
    theme: style_mod.Theme,
};

const HelpRow = struct {
    keys: []const u8,
    action: []const u8,
};

const description = "A terminal user interface for BoardGameGeek.";
const repository_url = "https://github.com/hiroaqii/bgg-tui";

const global_rows = [_]HelpRow{
    .{ .keys = "↑/↓/j/k", .action = "move / scroll" },
    .{ .keys = "Enter", .action = "open / select / save" },
    .{ .keys = "Esc/b", .action = "back / cancel" },
    .{ .keys = "m", .action = "main menu" },
    .{ .keys = "q", .action = "quit" },
    .{ .keys = "?", .action = "toggle help" },
};

const screen_rows = [_]HelpRow{
    .{ .keys = "h", .action = "hot games" },
    .{ .keys = "/", .action = "search or filter" },
    .{ .keys = "c", .action = "collection" },
    .{ .keys = "s", .action = "settings / sort / status" },
    .{ .keys = "o", .action = "open BGG page" },
    .{ .keys = "f", .action = "forums from game detail" },
    .{ .keys = "n/p", .action = "next / previous page" },
};

pub fn draw(surface: *chasen.Surface, opts: Options) void {
    surface.hideCursor();

    const frame = ui.Overlay.frame(surface, .{
        .size = .{ .width = 68, .height = 26 },
        .panel = .{
            .title = "Help",
            .border = opts.border,
            .border_style = opts.theme.border,
            .title_style = opts.theme.title,
        },
    }) orelse return;
    frame.view();

    var content = frame.contentSurface();
    const size = content.size();
    if (size.width == 0 or size.height == 0) return;
    const body_limit = size.height -| 1;

    var row: u16 = 0;
    const title = std.fmt.allocPrint(content.frameAllocator(), "bgg-tui {s}", .{opts.version}) catch "bgg-tui";
    drawCenteredText(&content, row, title, opts.theme.title);
    row += 1;
    drawCenteredText(&content, row, description, opts.theme.muted);
    row += 1;
    drawCenteredText(&content, row, repository_url, opts.theme.subtle);
    row += 2;

    row = drawSection(&content, row, body_limit, "Global", &global_rows, opts.theme);
    if (row < body_limit) row += 1;
    row = drawSection(&content, row, body_limit, "Screens and actions", &screen_rows, opts.theme);

    if (row + 1 < body_limit) {
        row += 1;
        _ = content.borrowTextAt(0, row, "Filter and text inputs keep printable keys as text.", opts.theme.subtle);
    }

    if (size.height > 0) {
        drawCenteredText(&content, size.height - 1, "Press any key to close", opts.theme.subtle);
    }
}

fn drawSection(surface: *chasen.Surface, row: u16, body_limit: u16, title: []const u8, rows: []const HelpRow, theme: style_mod.Theme) u16 {
    var current = row;
    if (current >= body_limit) return current;
    _ = surface.borrowTextAt(0, current, title, theme.title);
    current += 1;

    for (rows) |help_row| {
        if (current >= body_limit) return current;
        drawItemRow(surface, current, help_row, theme);
        current += 1;
    }
    return current;
}

fn drawItemRow(surface: *chasen.Surface, row: u16, help_row: HelpRow, theme: style_mod.Theme) void {
    const action_col: u16 = 18;
    _ = surface.borrowTextAt(0, row, help_row.keys, theme.focused);
    if (surface.size().width > action_col) {
        _ = surface.borrowTextAt(action_col, row, help_row.action, theme.muted);
    }
}

fn drawCenteredText(surface: *chasen.Surface, row: u16, value: []const u8, style: chasen.TextStyle) void {
    if (surface.size().height <= row) return;
    const width = chasen.text.displayWidth(value);
    const col: u16 = if (width >= surface.size().width) 0 else (surface.size().width - width) / 2;
    _ = surface.borrowTextAt(col, row, value, style);
}

test "help overlay renders app summary and close hint below action rows" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(68, 26);
    defer ts.deinit();

    draw(&ts.surface, .{
        .version = "0.4.0-dev",
        .theme = style_mod.Theme.fromName("default"),
    });

    try ts.expectCellText(2, 3, "h");
    try std.testing.expectEqualStrings("o", ts.surface.readCell(2, 19).?.char.grapheme);
    try ts.expectCellText(2, 23, "P");
}
