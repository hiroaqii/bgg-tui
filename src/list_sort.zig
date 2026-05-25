pub const Mode = enum {
    source,
    name_asc,

    pub fn next(self: Mode) Mode {
        return switch (self) {
            .source => .name_asc,
            .name_asc => .source,
        };
    }

    pub fn label(self: Mode, context: Context) []const u8 {
        return switch (self) {
            .source => switch (context) {
                .hot_games => "rank",
                .search_results => "relevance",
            },
            .name_asc => "name",
        };
    }
};

pub const Context = enum {
    hot_games,
    search_results,
};
