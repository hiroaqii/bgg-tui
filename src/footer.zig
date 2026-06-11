const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

pub const Item = ui.key_hint.Item;

pub const DrawOptions = struct {
    max_lines: u16 = 1,
    overflow: ui.key_hint.Overflow = .ellipsis,
};

pub fn item(keys: []const u8, action: []const u8) Item {
    return ui.key_hint.item(keys, action);
}

pub const common = struct {
    pub const move = item("↑/↓/j/k", "move");
    pub const move_vertical = item("↑/↓", "move");
    pub const scroll = item("↑/↓/j/k", "scroll");

    pub const open = item("Enter", "open");
    pub const detail = item("Enter", "detail");
    pub const save = item("Enter", "save");
    pub const cancel = item("Esc", "cancel");
    pub const clear = item("Esc", "clear");
    pub const filter = item("/", "filter");
    pub const sort = item("s", "sort");
    pub const menu = item("m", "menu");
    pub const menu_esc = item("Esc", "menu");
    pub const quit = item("q", "quit");
    pub const quit_esc = item("Esc/q", "quit");
};

pub fn draw(surface: *chasen.Surface, row: u16, items: []const Item, style: chasen.TextStyle, opts: DrawOptions) ui.key_hint.DrawResult {
    return ui.key_hint.draw(surface, 0, row, items, drawOptions(style, opts));
}

pub fn drawCentered(surface: *chasen.Surface, row: u16, items: []const Item, style: chasen.TextStyle, opts: DrawOptions) ui.key_hint.DrawResult {
    const chasen_opts = drawOptions(style, opts);
    const footer_width = ui.key_hint.width(items, chasen_opts);
    const size = surface.size();
    const col: u16 = if (footer_width >= size.width) 0 else (size.width - footer_width) / 2;
    return ui.key_hint.draw(surface, col, row, items, chasen_opts);
}

pub fn allocText(allocator: std.mem.Allocator, items: []const Item, opts: ui.key_hint.DrawOptions) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    for (items, 0..) |footer_item, index| {
        if (index > 0) try out.writer.writeAll(opts.separator);
        try out.writer.writeAll(footer_item.keys);
        try out.writer.writeAll(opts.delimiter);
        try out.writer.writeAll(footer_item.action);
    }

    return out.toOwnedSlice();
}

pub fn drawOptions(style: chasen.TextStyle, opts: DrawOptions) ui.key_hint.DrawOptions {
    var key_style = style;
    key_style.bold = true;
    return .{
        .style = style,
        .key_style = key_style,
        .max_lines = opts.max_lines,
        .overflow = opts.overflow,
    };
}
