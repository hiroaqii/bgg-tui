pub const name = "bgg-tui";
pub const version = "0.0.0";

pub const app = @import("app.zig");
pub const bgg = @import("bgg/root.zig");
pub const config = @import("config.zig");
pub const format = @import("format.zig");
pub const labels = @import("labels.zig");
pub const list_filter = @import("list_filter.zig");
pub const list_view = @import("list_view.zig");

test {
    _ = app;
    _ = bgg;
    _ = config;
    _ = format;
    _ = labels;
    _ = list_filter;
    _ = list_view;
}
