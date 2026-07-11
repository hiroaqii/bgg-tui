const std = @import("std");

const bgg_client = @import("../bgg/client.zig");
const bgg_endpoint = @import("../bgg/endpoint.zig");
const bgg_error = @import("../bgg/error.zig");
const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");

pub const HotGamesResult = union(enum) {
    ok: []bgg_model.HotGame,
    failed: []const u8,

    pub fn deinit(self: *HotGamesResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |games| bgg_xml.freeHotGames(allocator, games),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const HotGameStatsResult = struct {
    request_id: u64,
    result: Result,

    pub const Result = union(enum) {
        ok: []bgg_model.Game,
        failed: []const u8,

        pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .ok => |games| bgg_xml.freeGames(allocator, games),
                .failed => {},
            }
            self.* = undefined;
        }
    };

    pub fn deinit(self: *HotGameStatsResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const SearchResult = union(enum) {
    ok: []bgg_model.GameSearchResult,
    failed: []const u8,

    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |results| bgg_xml.freeSearchResults(allocator, results),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const SearchTaskResult = struct {
    request_id: u64,
    result: SearchResult,

    pub fn deinit(self: *SearchTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const CollectionResult = union(enum) {
    ok: []bgg_model.CollectionItem,
    failed: []const u8,

    pub fn deinit(self: *CollectionResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |items| bgg_xml.freeCollectionItems(allocator, items),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const CollectionTaskResult = struct {
    request_id: u64,
    result: CollectionResult,

    pub fn deinit(self: *CollectionTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const GameDetailResult = union(enum) {
    ok: []bgg_model.Game,
    failed: []const u8,

    pub fn deinit(self: *GameDetailResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |games| bgg_xml.freeGames(allocator, games),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const GameDetailTaskResult = struct {
    request_id: u64,
    result: GameDetailResult,

    pub fn deinit(self: *GameDetailTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const ForumListResult = union(enum) {
    ok: []bgg_model.Forum,
    failed: []const u8,

    pub fn deinit(self: *ForumListResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |forums| bgg_xml.freeForums(allocator, forums),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const ForumListTaskResult = struct {
    request_id: u64,
    result: ForumListResult,

    pub fn deinit(self: *ForumListTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const ForumThreadsResult = union(enum) {
    ok: bgg_model.ThreadList,
    failed: []const u8,

    pub fn deinit(self: *ForumThreadsResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |thread_list| bgg_xml.freeThreadList(allocator, thread_list),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const ForumThreadsTaskResult = struct {
    request_id: u64,
    result: ForumThreadsResult,

    pub fn deinit(self: *ForumThreadsTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub const ThreadResult = union(enum) {
    ok: bgg_model.Thread,
    failed: []const u8,

    pub fn deinit(self: *ThreadResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |thread| bgg_xml.freeThread(allocator, thread),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub const ThreadTaskResult = struct {
    request_id: u64,
    result: ThreadResult,

    pub fn deinit(self: *ThreadTaskResult, allocator: std.mem.Allocator) void {
        self.result.deinit(allocator);
        self.* = undefined;
    }
};

pub fn loadHotGames(allocator: std.mem.Allocator, io: std.Io, token: []const u8) !HotGamesResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.hot(allocator);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const games = bgg_xml.parseHotResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = games };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadHotGameStats(allocator: std.mem.Allocator, io: std.Io, token: []const u8, ids: []const u32) !HotGameStatsResult.Result {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    var stats: std.ArrayList(bgg_model.Game) = .empty;
    errdefer {
        bgg_xml.freeGameItems(allocator, stats.items);
        stats.deinit(allocator);
    }

    var start: usize = 0;
    while (start < ids.len) {
        const end = @min(start + bgg_endpoint.max_thing_ids, ids.len);
        const path = try bgg_endpoint.thing(allocator, ids[start..end]);
        defer allocator.free(path);

        const result = try client.getPath(path, .generic);
        switch (result) {
            .ok => |response| {
                defer response.deinit(allocator);
                const batch = bgg_xml.parseThingResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
                };
                var batch_owned = true;
                errdefer if (batch_owned) bgg_xml.freeGameItems(allocator, batch);
                defer allocator.free(batch);
                try stats.appendSlice(allocator, batch);
                batch_owned = false;
            },
            .api_error => |err| return .{ .failed = apiErrorMessage(err) },
        }

        start = end;
    }

    return .{ .ok = try stats.toOwnedSlice(allocator) };
}

pub fn loadSearchResults(allocator: std.mem.Allocator, io: std.Io, token: []const u8, query: []const u8) !SearchResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.search(allocator, query);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const results = bgg_xml.parseSearchResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = results };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadCollectionItems(
    allocator: std.mem.Allocator,
    io: std.Io,
    token: []const u8,
    username: []const u8,
) !CollectionResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.collection(allocator, username, .{});
    defer allocator.free(path);

    const result = try client.getPath(path, .collection);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const items = bgg_xml.parseCollectionResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = items };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadGameDetail(allocator: std.mem.Allocator, io: std.Io, token: []const u8, game_id: u32) !GameDetailResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const ids = [_]u32{game_id};
    const path = try bgg_endpoint.thing(allocator, &ids);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const games = bgg_xml.parseThingResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = games };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadForumList(allocator: std.mem.Allocator, io: std.Io, token: []const u8, game_id: u32) !ForumListResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.forumList(allocator, game_id);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const forums = bgg_xml.parseForumListResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = forums };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadForumThreads(allocator: std.mem.Allocator, io: std.Io, token: []const u8, forum_id: u32, page: u32) !ForumThreadsResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const requested_page = if (page == 0) 1 else page;
    const path = try bgg_endpoint.forum(allocator, forum_id, requested_page);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const threads = bgg_xml.parseForumResponse(allocator, response.body, requested_page) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = threads };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

pub fn loadThread(allocator: std.mem.Allocator, io: std.Io, token: []const u8, thread_id: u32) !ThreadResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.thread(allocator, thread_id);
    defer allocator.free(path);

    const result = try client.getPath(path, .generic);
    switch (result) {
        .ok => |response| {
            defer response.deinit(allocator);
            const thread = bgg_xml.parseThreadResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return .{ .failed = apiErrorMessage(bgg_error.classifyParseError(parse_error)) },
            };
            return .{ .ok = thread };
        },
        .api_error => |err| return .{ .failed = apiErrorMessage(err) },
    }
}

fn apiErrorMessage(err: bgg_error.ApiError) []const u8 {
    return switch (err) {
        .auth => |auth| auth.message,
        .rate_limit => |rate_limit| rate_limit.message,
        .not_found => "BGG API resource was not found",
        .network => |network| network.message,
        .parse => |parse| parse.message,
    };
}
