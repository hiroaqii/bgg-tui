const build_options = @import("build_options");

pub const name = "bgg-tui";
pub const version = build_options.version;

pub const app = @import("app.zig");
pub const bgg = @import("bgg/root.zig");
pub const browser = @import("browser.zig");
pub const config = @import("config.zig");
pub const column_list_view = @import("column_list_view.zig");
pub const features = @import("features/root.zig");
pub const format = @import("format.zig");
pub const image = @import("image.zig");
pub const labels = @import("labels.zig");
pub const layout = @import("layout.zig");
pub const line_blocks = @import("line_blocks.zig");
pub const list_filter = @import("list_filter.zig");
pub const list_sort = @import("list_sort.zig");
pub const list_view = @import("list_view.zig");
pub const motion = @import("motion.zig");
pub const paste = @import("paste.zig");
pub const screens = @import("screens/root.zig");
pub const style = @import("style.zig");
pub const tasks = @import("tasks/root.zig");

test {
    _ = app;
    _ = bgg;
    _ = browser;
    _ = config;
    _ = column_list_view;
    _ = features;
    _ = format;
    _ = image;
    _ = labels;
    _ = layout;
    _ = line_blocks;
    _ = list_filter;
    _ = list_sort;
    _ = list_view;
    _ = motion;
    _ = paste;
    _ = screens;
    _ = style;
    _ = tasks;
}
