pub const name = "bgg-tui";
pub const version = "0.0.0";

pub const bgg = @import("bgg/root.zig");
pub const config = @import("config.zig");

test {
    _ = bgg;
    _ = config;
}
