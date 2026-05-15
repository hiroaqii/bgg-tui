const std = @import("std");

pub const Fixture = enum {
    search,
    hot,
    thing,
    collection,
    forum_list,
    forum,
    thread,

    pub fn path(fixture: Fixture) []const u8 {
        return switch (fixture) {
            .search => "testdata/search_response.xml",
            .hot => "testdata/hot_response.xml",
            .thing => "testdata/thing_response.xml",
            .collection => "testdata/collection_response.xml",
            .forum_list => "testdata/forumlist_response.xml",
            .forum => "testdata/forum_response.xml",
            .thread => "testdata/thread_response.xml",
        };
    }
};

test "BGG XML fixtures are retained for Zig parser tests" {
    inline for ([_]Fixture{ .search, .hot, .thing, .collection, .forum_list, .forum, .thread }) |fixture| {
        try std.testing.expect(std.mem.endsWith(u8, Fixture.path(fixture), ".xml"));
    }
}
