pub const detail = @import("detail.zig");
pub const forum = @import("forum.zig");
pub const hot_games = @import("hot_games.zig");
pub const search = @import("search.zig");
pub const settings = @import("settings.zig");
pub const thread = @import("thread.zig");

test {
    _ = detail;
    _ = forum;
    _ = hot_games;
    _ = search;
    _ = settings;
    _ = thread;
}
