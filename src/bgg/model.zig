const std = @import("std");

pub const GameSearchResult = struct {
    id: u32,
    name: []const u8,
    year_published: ?i32 = null,
};

pub const HotGame = struct {
    id: u32,
    rank: u32,
    name: []const u8,
    thumbnail_url: ?[]const u8 = null,
    year_published: ?i32 = null,
};

pub const PlayerCountVotes = struct {
    num_players: []const u8,
    best: u32 = 0,
    recommended: u32 = 0,
    not_recommended: u32 = 0,
};

pub const PlayerCountPoll = struct {
    total_votes: u32 = 0,
    results: []PlayerCountVotes = &.{},
    best_with: ?[]const u8 = null,
    recommended_with: ?[]const u8 = null,
};

pub const Game = struct {
    id: u32,
    name: []const u8,
    year_published: ?i32 = null,
    description: []const u8 = "",
    thumbnail_url: ?[]const u8 = null,
    image_url: ?[]const u8 = null,
    min_players: u32 = 0,
    max_players: u32 = 0,
    playing_time: u32 = 0,
    min_play_time: u32 = 0,
    max_play_time: u32 = 0,
    min_age: u32 = 0,
    rating: f64 = 0,
    users_rated: u32 = 0,
    bayes_average: f64 = 0,
    rank: u32 = 0,
    weight: f64 = 0,
    stddev: f64 = 0,
    median: f64 = 0,
    owned: u32 = 0,
    num_comments: u32 = 0,
    num_weights: u32 = 0,
    designers: []const []const u8 = &.{},
    artists: []const []const u8 = &.{},
    publishers: []const []const u8 = &.{},
    categories: []const []const u8 = &.{},
    mechanics: []const []const u8 = &.{},
    player_count_poll: ?PlayerCountPoll = null,
};

pub const CollectionItem = struct {
    id: u32,
    name: []const u8,
    year_published: ?i32 = null,
    image_url: ?[]const u8 = null,
    thumbnail_url: ?[]const u8 = null,
    num_plays: u32 = 0,
    rating: f64 = 0,
    bgg_rating: f64 = 0,
    bayes_average: f64 = 0,
    rank: u32 = 0,
    owned: bool = false,
    prev_owned: bool = false,
    for_trade: bool = false,
    want: bool = false,
    want_to_play: bool = false,
    want_to_buy: bool = false,
    wishlist: bool = false,
    preordered: bool = false,
};

pub const Forum = struct {
    id: u32,
    title: []const u8,
    description: []const u8 = "",
    num_threads: u32 = 0,
    num_posts: u32 = 0,
    last_post_date: []const u8 = "",
};

pub const ThreadSummary = struct {
    id: u32,
    subject: []const u8,
    author: []const u8,
    num_articles: u32 = 0,
    post_date: []const u8 = "",
    last_post_date: []const u8 = "",
};

pub const ThreadList = struct {
    threads: []ThreadSummary = &.{},
    page: u32 = 1,
    total_pages: u32 = 1,
};

pub const Article = struct {
    id: u32,
    username: []const u8,
    post_date: []const u8 = "",
    body: []const u8 = "",
};

pub const Thread = struct {
    id: u32,
    subject: []const u8,
    articles: []Article = &.{},
    page: u32 = 1,
    total_pages: u32 = 1,
};

test "model declarations compile" {
    const result = GameSearchResult{ .id = 1, .name = "Gloomhaven" };
    try std.testing.expectEqual(@as(u32, 1), result.id);
}
