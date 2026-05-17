pub const name = "bgg-tui";
pub const version = "0.0.0";

pub const app = @import("app.zig");
pub const bgg = @import("bgg/root.zig");
pub const config = @import("config.zig");
pub const format = @import("format.zig");

test {
    _ = app;
    _ = bgg;
    _ = config;
    _ = format;
}
