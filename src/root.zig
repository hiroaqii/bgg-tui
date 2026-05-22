pub const name = "bgg-tui";
pub const version = "0.0.0";

pub const app = @import("app.zig");
pub const bgg = @import("bgg/root.zig");
pub const browser = @import("browser.zig");
pub const config = @import("config.zig");
pub const format = @import("format.zig");
pub const labels = @import("labels.zig");
pub const list_filter = @import("list_filter.zig");
pub const list_view = @import("list_view.zig");
pub const motion = @import("motion.zig");
pub const screens = @import("screens/root.zig");
pub const style = @import("style.zig");

test {
    _ = app;
    _ = bgg;
    _ = browser;
    _ = config;
    _ = format;
    _ = labels;
    _ = list_filter;
    _ = list_view;
    _ = motion;
    _ = screens;
    _ = style;
}
