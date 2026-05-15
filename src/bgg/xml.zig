const std = @import("std");
const xml_lib = @import("xml");

const model = @import("model.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    MissingRequiredAttribute,
    MissingName,
    MissingPrimaryName,
    UnexpectedEndOfDocument,
    UnexpectedElementEnd,
};

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

pub fn parseSearchResponse(allocator: Allocator, bytes: []const u8) ![]model.GameSearchResult {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    var results: std.ArrayList(model.GameSearchResult) = .empty;
    errdefer {
        for (results.items) |item| {
            allocator.free(item.name);
        }
        results.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => break,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    try results.append(allocator, try parseSearchItem(allocator, reader));
                }
            },
            .element_end => continue,
        }
    }

    return results.toOwnedSlice(allocator);
}

pub fn parseHotResponse(allocator: Allocator, bytes: []const u8) ![]model.HotGame {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    var results: std.ArrayList(model.HotGame) = .empty;
    errdefer {
        freeHotGameItems(allocator, results.items);
        results.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => break,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    try results.append(allocator, try parseHotItem(allocator, reader));
                }
            },
            .element_end => continue,
        }
    }

    return results.toOwnedSlice(allocator);
}

pub fn parseThingResponse(allocator: Allocator, bytes: []const u8) ![]model.Game {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    var games: std.ArrayList(model.Game) = .empty;
    errdefer {
        freeGameItems(allocator, games.items);
        games.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => break,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    try games.append(allocator, try parseThingItem(allocator, reader));
                }
            },
            .element_end => continue,
        }
    }

    return games.toOwnedSlice(allocator);
}

pub fn parseCollectionResponse(allocator: Allocator, bytes: []const u8) ![]model.CollectionItem {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    var items: std.ArrayList(model.CollectionItem) = .empty;
    errdefer {
        freeCollectionItemsOnly(allocator, items.items);
        items.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => break,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    try items.append(allocator, try parseCollectionItem(allocator, reader));
                }
            },
            .element_end => continue,
        }
    }

    return items.toOwnedSlice(allocator);
}

pub fn parseForumListResponse(allocator: Allocator, bytes: []const u8) ![]model.Forum {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    var forums: std.ArrayList(model.Forum) = .empty;
    errdefer {
        freeForumItems(allocator, forums.items);
        forums.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => break,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "forum")) {
                    try forums.append(allocator, try parseForumListItem(allocator, reader));
                }
            },
            .element_end => continue,
        }
    }

    return forums.toOwnedSlice(allocator);
}

pub fn freeSearchResults(allocator: Allocator, results: []model.GameSearchResult) void {
    for (results) |item| {
        allocator.free(item.name);
    }
    allocator.free(results);
}

pub fn freeHotGames(allocator: Allocator, games: []model.HotGame) void {
    freeHotGameItems(allocator, games);
    allocator.free(games);
}

pub fn freeGames(allocator: Allocator, games: []model.Game) void {
    freeGameItems(allocator, games);
    allocator.free(games);
}

pub fn freeCollectionItems(allocator: Allocator, items: []model.CollectionItem) void {
    freeCollectionItemsOnly(allocator, items);
    allocator.free(items);
}

pub fn freeForums(allocator: Allocator, forums: []model.Forum) void {
    freeForumItems(allocator, forums);
    allocator.free(forums);
}

fn parseSearchItem(allocator: Allocator, reader: *xml_lib.Reader) !model.GameSearchResult {
    const id = try parseU32Attribute(reader, "id");

    var name: ?[]const u8 = null;
    errdefer if (name) |value| allocator.free(value);

    var year_published: ?i32 = null;

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "name")) {
                    if (isAttributeValue(reader, "type", "primary")) {
                        if (name) |old| allocator.free(old);
                        name = try dupeAttributeValue(allocator, reader, "value");
                    }
                    try reader.skipElement();
                } else if (std.mem.eql(u8, reader.elementName(), "yearpublished")) {
                    year_published = try parseI32Attribute(reader, "value");
                    try reader.skipElement();
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    return .{
                        .id = id,
                        .name = name orelse return ParseError.MissingPrimaryName,
                        .year_published = year_published,
                    };
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseHotItem(allocator: Allocator, reader: *xml_lib.Reader) !model.HotGame {
    const id = try parseU32Attribute(reader, "id");
    const rank = try parseU32Attribute(reader, "rank");

    var name: ?[]const u8 = null;
    errdefer if (name) |value| allocator.free(value);

    var thumbnail_url: ?[]const u8 = null;
    errdefer if (thumbnail_url) |value| allocator.free(value);

    var year_published: ?i32 = null;

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "thumbnail")) {
                    if (thumbnail_url) |old| allocator.free(old);
                    thumbnail_url = try dupeAttributeValue(allocator, reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, reader.elementName(), "name")) {
                    if (name) |old| allocator.free(old);
                    name = try dupeAttributeValue(allocator, reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, reader.elementName(), "yearpublished")) {
                    year_published = try parseI32Attribute(reader, "value");
                    try reader.skipElement();
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    return .{
                        .id = id,
                        .rank = rank,
                        .name = name orelse return ParseError.MissingName,
                        .thumbnail_url = thumbnail_url,
                        .year_published = year_published,
                    };
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseThingItem(allocator: Allocator, reader: *xml_lib.Reader) !model.Game {
    var builder: GameBuilder = .{
        .allocator = allocator,
        .game = .{
            .id = try parseU32Attribute(reader, "id"),
            .name = "",
        },
    };
    errdefer builder.deinit();

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                const element_name = reader.elementName();
                if (std.mem.eql(u8, element_name, "thumbnail")) {
                    replaceOptionalString(allocator, &builder.game.thumbnail_url, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "image")) {
                    replaceOptionalString(allocator, &builder.game.image_url, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "name")) {
                    if (isAttributeValue(reader, "type", "primary")) {
                        replaceRequiredString(allocator, &builder.game.name, try dupeAttributeValue(allocator, reader, "value"));
                    }
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "description")) {
                    replaceRequiredString(allocator, &builder.game.description, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "yearpublished")) {
                    builder.game.year_published = try parseI32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "minplayers")) {
                    builder.game.min_players = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "maxplayers")) {
                    builder.game.max_players = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "playingtime")) {
                    builder.game.playing_time = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "minplaytime")) {
                    builder.game.min_play_time = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "maxplaytime")) {
                    builder.game.max_play_time = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "minage")) {
                    builder.game.min_age = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "link")) {
                    try parseThingLink(&builder, reader);
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "poll")) {
                    if (isAttributeValue(reader, "name", "suggested_numplayers")) {
                        if (builder.game.player_count_poll) |poll| freePlayerCountPoll(allocator, poll);
                        builder.game.player_count_poll = try parsePlayerCountPoll(allocator, reader);
                    } else {
                        try reader.skipElement();
                    }
                } else if (std.mem.eql(u8, element_name, "poll-summary")) {
                    if (isAttributeValue(reader, "name", "suggested_numplayers")) {
                        try parsePlayerCountSummary(allocator, reader, &builder.game.player_count_poll);
                    } else {
                        try reader.skipElement();
                    }
                } else if (std.mem.eql(u8, element_name, "statistics")) {
                    try parseStatistics(reader, &builder.game);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    if (builder.game.name.len == 0) return ParseError.MissingPrimaryName;
                    return try builder.finish();
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseCollectionItem(allocator: Allocator, reader: *xml_lib.Reader) !model.CollectionItem {
    var item: model.CollectionItem = .{
        .id = try parseU32Attribute(reader, "objectid"),
        .name = "",
    };
    errdefer freeCollectionItem(allocator, item);

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                const element_name = reader.elementName();
                if (std.mem.eql(u8, element_name, "name")) {
                    replaceRequiredString(allocator, &item.name, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "yearpublished")) {
                    item.year_published = try parseElementTextI32(reader);
                } else if (std.mem.eql(u8, element_name, "image")) {
                    replaceOptionalString(allocator, &item.image_url, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "thumbnail")) {
                    replaceOptionalString(allocator, &item.thumbnail_url, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, element_name, "status")) {
                    parseCollectionStatus(reader, &item);
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "numplays")) {
                    item.num_plays = try parseElementTextU32(reader);
                } else if (std.mem.eql(u8, element_name, "stats")) {
                    try parseCollectionStats(reader, &item);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "item")) {
                    if (item.name.len == 0) return ParseError.MissingName;
                    return item;
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseForumListItem(allocator: Allocator, reader: *xml_lib.Reader) !model.Forum {
    const forum: model.Forum = .{
        .id = try parseU32Attribute(reader, "id"),
        .title = try dupeAttributeValue(allocator, reader, "title"),
        .description = try dupeAttributeValue(allocator, reader, "description"),
        .num_threads = try parseU32Attribute(reader, "numthreads"),
        .num_posts = try parseU32Attribute(reader, "numposts"),
        .last_post_date = try dupeAttributeValue(allocator, reader, "lastpostdate"),
    };
    errdefer freeForum(allocator, forum);

    try reader.skipElement();
    return forum;
}

fn freeHotGameItems(allocator: Allocator, games: []model.HotGame) void {
    for (games) |game| {
        allocator.free(game.name);
        if (game.thumbnail_url) |thumbnail_url| allocator.free(thumbnail_url);
    }
}

fn freeGameItems(allocator: Allocator, games: []model.Game) void {
    for (games) |game| {
        freeGame(allocator, game);
    }
}

fn freeGame(allocator: Allocator, game: model.Game) void {
    if (game.name.len > 0) allocator.free(game.name);
    if (game.description.len > 0) allocator.free(game.description);
    if (game.thumbnail_url) |thumbnail_url| allocator.free(thumbnail_url);
    if (game.image_url) |image_url| allocator.free(image_url);
    freeStringList(allocator, game.designers);
    freeStringList(allocator, game.artists);
    freeStringList(allocator, game.publishers);
    freeStringList(allocator, game.categories);
    freeStringList(allocator, game.mechanics);
    if (game.player_count_poll) |poll| freePlayerCountPoll(allocator, poll);
}

fn freeStringList(allocator: Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
}

fn freePlayerCountPoll(allocator: Allocator, poll: model.PlayerCountPoll) void {
    for (poll.results) |result| {
        allocator.free(result.num_players);
    }
    allocator.free(poll.results);
    if (poll.best_with) |value| allocator.free(value);
    if (poll.recommended_with) |value| allocator.free(value);
}

const GameBuilder = struct {
    allocator: Allocator,
    game: model.Game,
    designers: std.ArrayList([]const u8) = .empty,
    artists: std.ArrayList([]const u8) = .empty,
    publishers: std.ArrayList([]const u8) = .empty,
    categories: std.ArrayList([]const u8) = .empty,
    mechanics: std.ArrayList([]const u8) = .empty,

    fn deinit(builder: *GameBuilder) void {
        freeGame(builder.allocator, builder.game);
        freeStringListItems(builder.allocator, builder.designers.items);
        builder.designers.deinit(builder.allocator);
        freeStringListItems(builder.allocator, builder.artists.items);
        builder.artists.deinit(builder.allocator);
        freeStringListItems(builder.allocator, builder.publishers.items);
        builder.publishers.deinit(builder.allocator);
        freeStringListItems(builder.allocator, builder.categories.items);
        builder.categories.deinit(builder.allocator);
        freeStringListItems(builder.allocator, builder.mechanics.items);
        builder.mechanics.deinit(builder.allocator);
    }

    fn finish(builder: *GameBuilder) !model.Game {
        errdefer builder.deinit();
        builder.game.designers = try builder.designers.toOwnedSlice(builder.allocator);
        builder.game.artists = try builder.artists.toOwnedSlice(builder.allocator);
        builder.game.publishers = try builder.publishers.toOwnedSlice(builder.allocator);
        builder.game.categories = try builder.categories.toOwnedSlice(builder.allocator);
        builder.game.mechanics = try builder.mechanics.toOwnedSlice(builder.allocator);
        const game = builder.game;
        builder.* = undefined;
        return game;
    }
};

fn freeStringListItems(allocator: Allocator, values: []const []const u8) void {
    for (values) |value| {
        allocator.free(value);
    }
}

fn freeCollectionItemsOnly(allocator: Allocator, items: []model.CollectionItem) void {
    for (items) |item| {
        freeCollectionItem(allocator, item);
    }
}

fn freeCollectionItem(allocator: Allocator, item: model.CollectionItem) void {
    if (item.name.len > 0) allocator.free(item.name);
    if (item.image_url) |image_url| allocator.free(image_url);
    if (item.thumbnail_url) |thumbnail_url| allocator.free(thumbnail_url);
}

fn freeForumItems(allocator: Allocator, forums: []model.Forum) void {
    for (forums) |forum| {
        freeForum(allocator, forum);
    }
}

fn freeForum(allocator: Allocator, forum: model.Forum) void {
    allocator.free(forum.title);
    if (forum.description.len > 0) allocator.free(forum.description);
    if (forum.last_post_date.len > 0) allocator.free(forum.last_post_date);
}

fn parseThingLink(builder: *GameBuilder, reader: *xml_lib.Reader) !void {
    const link_type = try attributeValue(reader, "type");
    const value = try dupeAttributeValue(builder.allocator, reader, "value");
    errdefer builder.allocator.free(value);

    if (std.mem.eql(u8, link_type, "boardgamedesigner")) {
        try builder.designers.append(builder.allocator, value);
    } else if (std.mem.eql(u8, link_type, "boardgameartist")) {
        try builder.artists.append(builder.allocator, value);
    } else if (std.mem.eql(u8, link_type, "boardgamepublisher")) {
        try builder.publishers.append(builder.allocator, value);
    } else if (std.mem.eql(u8, link_type, "boardgamecategory")) {
        try builder.categories.append(builder.allocator, value);
    } else if (std.mem.eql(u8, link_type, "boardgamemechanic")) {
        try builder.mechanics.append(builder.allocator, value);
    } else {
        builder.allocator.free(value);
    }
}

fn parsePlayerCountPoll(allocator: Allocator, reader: *xml_lib.Reader) !model.PlayerCountPoll {
    var poll: model.PlayerCountPoll = .{
        .total_votes = try parseU32Attribute(reader, "totalvotes"),
    };
    errdefer freePlayerCountPoll(allocator, poll);

    var results: std.ArrayList(model.PlayerCountVotes) = .empty;
    errdefer {
        for (results.items) |result| allocator.free(result.num_players);
        results.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "results")) {
                    try results.append(allocator, try parsePlayerCountVotes(allocator, reader));
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "poll")) {
                    poll.results = try results.toOwnedSlice(allocator);
                    return poll;
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parsePlayerCountVotes(allocator: Allocator, reader: *xml_lib.Reader) !model.PlayerCountVotes {
    var votes: model.PlayerCountVotes = .{
        .num_players = try dupeAttributeValue(allocator, reader, "numplayers"),
    };
    errdefer allocator.free(votes.num_players);

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "result")) {
                    const value = try attributeValue(reader, "value");
                    const num_votes = try parseU32Attribute(reader, "numvotes");
                    if (std.mem.eql(u8, value, "Best")) {
                        votes.best = num_votes;
                    } else if (std.mem.eql(u8, value, "Recommended")) {
                        votes.recommended = num_votes;
                    } else if (std.mem.eql(u8, value, "Not Recommended")) {
                        votes.not_recommended = num_votes;
                    }
                    try reader.skipElement();
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "results")) return votes;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parsePlayerCountSummary(allocator: Allocator, reader: *xml_lib.Reader, poll: *?model.PlayerCountPoll) !void {
    if (poll.* == null) {
        poll.* = .{};
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "result")) {
                    const name = try attributeValue(reader, "name");
                    if (std.mem.eql(u8, name, "bestwith")) {
                        replaceOptionalString(allocator, &poll.*.?.best_with, try dupeAttributeValue(allocator, reader, "value"));
                    } else if (std.mem.eql(u8, name, "recommmendedwith") or std.mem.eql(u8, name, "recommendedwith")) {
                        replaceOptionalString(allocator, &poll.*.?.recommended_with, try dupeAttributeValue(allocator, reader, "value"));
                    }
                    try reader.skipElement();
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "poll-summary")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseStatistics(reader: *xml_lib.Reader, game: *model.Game) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "ratings")) {
                    try parseRatings(reader, game);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "statistics")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseRatings(reader: *xml_lib.Reader, game: *model.Game) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                const element_name = reader.elementName();
                if (std.mem.eql(u8, element_name, "usersrated")) {
                    game.users_rated = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "average")) {
                    game.rating = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "bayesaverage")) {
                    game.bayes_average = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "ranks")) {
                    try parseRanks(reader, game);
                } else if (std.mem.eql(u8, element_name, "stddev")) {
                    game.stddev = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "median")) {
                    game.median = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "owned")) {
                    game.owned = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "numcomments")) {
                    game.num_comments = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "numweights")) {
                    game.num_weights = try parseU32Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "averageweight")) {
                    game.weight = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "ratings")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseRanks(reader: *xml_lib.Reader, game: *model.Game) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "rank") and isAttributeValue(reader, "name", "boardgame")) {
                    game.rank = parseOptionalRank(reader);
                }
                try reader.skipElement();
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "ranks")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseCollectionStatus(reader: *xml_lib.Reader, item: *model.CollectionItem) void {
    item.owned = isAttributeValue(reader, "own", "1");
    item.prev_owned = isAttributeValue(reader, "prevowned", "1");
    item.for_trade = isAttributeValue(reader, "fortrade", "1");
    item.want = isAttributeValue(reader, "want", "1");
    item.want_to_play = isAttributeValue(reader, "wanttoplay", "1");
    item.want_to_buy = isAttributeValue(reader, "wanttobuy", "1");
    item.wishlist = isAttributeValue(reader, "wishlist", "1");
    item.preordered = isAttributeValue(reader, "preordered", "1");
}

fn parseCollectionStats(reader: *xml_lib.Reader, item: *model.CollectionItem) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "rating")) {
                    item.rating = parseOptionalF64Attribute(reader, "value");
                    try parseCollectionRating(reader, item);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "stats")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseCollectionRating(reader: *xml_lib.Reader, item: *model.CollectionItem) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                const element_name = reader.elementName();
                if (std.mem.eql(u8, element_name, "average")) {
                    item.bgg_rating = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "bayesaverage")) {
                    item.bayes_average = try parseF64Attribute(reader, "value");
                    try reader.skipElement();
                } else if (std.mem.eql(u8, element_name, "ranks")) {
                    try parseCollectionRanks(reader, item);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "rating")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseCollectionRanks(reader: *xml_lib.Reader, item: *model.CollectionItem) !void {
    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "rank") and isAttributeValue(reader, "name", "boardgame")) {
                    item.rank = parseOptionalRank(reader);
                }
                try reader.skipElement();
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "ranks")) return;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseU32Attribute(reader: *xml_lib.Reader, name: []const u8) !u32 {
    const value = try attributeValue(reader, name);
    return std.fmt.parseInt(u32, value, 10);
}

fn parseI32Attribute(reader: *xml_lib.Reader, name: []const u8) !i32 {
    const value = try attributeValue(reader, name);
    return std.fmt.parseInt(i32, value, 10);
}

fn parseF64Attribute(reader: *xml_lib.Reader, name: []const u8) !f64 {
    const value = try attributeValue(reader, name);
    return std.fmt.parseFloat(f64, value);
}

fn parseOptionalF64Attribute(reader: *xml_lib.Reader, name: []const u8) f64 {
    const value = attributeValue(reader, name) catch return 0;
    return std.fmt.parseFloat(f64, value) catch 0;
}

fn parseOptionalRank(reader: *xml_lib.Reader) u32 {
    const value = attributeValue(reader, "value") catch return 0;
    return std.fmt.parseInt(u32, value, 10) catch 0;
}

fn parseElementTextU32(reader: *xml_lib.Reader) !u32 {
    const value = try reader.readElementText();
    return std.fmt.parseInt(u32, value, 10);
}

fn parseElementTextI32(reader: *xml_lib.Reader) !i32 {
    const value = try reader.readElementText();
    return std.fmt.parseInt(i32, value, 10);
}

fn dupeAttributeValue(allocator: Allocator, reader: *xml_lib.Reader, name: []const u8) ![]const u8 {
    const index = reader.attributeIndex(name) orelse return ParseError.MissingRequiredAttribute;
    return try reader.attributeValueAlloc(allocator, index);
}

fn replaceRequiredString(allocator: Allocator, target: *[]const u8, value: []const u8) void {
    if (target.len > 0) allocator.free(target.*);
    target.* = value;
}

fn replaceOptionalString(allocator: Allocator, target: *?[]const u8, value: []const u8) void {
    if (target.*) |old| allocator.free(old);
    target.* = value;
}

fn isAttributeValue(reader: *xml_lib.Reader, name: []const u8, expected: []const u8) bool {
    const index = reader.attributeIndex(name) orelse return false;
    const value = reader.attributeValue(index) catch return false;
    return std.mem.eql(u8, value, expected);
}

fn attributeValue(reader: *xml_lib.Reader, name: []const u8) ![]const u8 {
    const index = reader.attributeIndex(name) orelse return ParseError.MissingRequiredAttribute;
    return try reader.attributeValue(index);
}

test "BGG XML fixtures are retained for Zig parser tests" {
    inline for ([_]Fixture{ .search, .hot, .thing, .collection, .forum_list, .forum, .thread }) |fixture| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            Fixture.path(fixture),
            std.testing.allocator,
            .limited(1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);

        try std.testing.expect(bytes.len > 0);
    }
}

test "parse search XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.search),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const results = try parseSearchResponse(std.testing.allocator, bytes);
    defer freeSearchResults(std.testing.allocator, results);

    try std.testing.expectEqual(@as(usize, 3), results.len);

    try std.testing.expectEqual(@as(u32, 13), results[0].id);
    try std.testing.expectEqualStrings("Catan", results[0].name);
    try std.testing.expectEqual(@as(?i32, 1995), results[0].year_published);

    try std.testing.expectEqual(@as(u32, 926), results[1].id);
    try std.testing.expectEqualStrings("Catan: Seafarers", results[1].name);
    try std.testing.expectEqual(@as(?i32, 1997), results[1].year_published);

    try std.testing.expectEqual(@as(u32, 278), results[2].id);
    try std.testing.expectEqualStrings("Catan Card Game", results[2].name);
    try std.testing.expectEqual(@as(?i32, 1996), results[2].year_published);
}

test "parse hot XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.hot),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const games = try parseHotResponse(std.testing.allocator, bytes);
    defer freeHotGames(std.testing.allocator, games);

    try std.testing.expectEqual(@as(usize, 5), games.len);

    try std.testing.expectEqual(@as(u32, 224517), games[0].id);
    try std.testing.expectEqual(@as(u32, 1), games[0].rank);
    try std.testing.expectEqualStrings("Brass: Birmingham", games[0].name);
    try std.testing.expectEqualStrings("https://cf.geekdo-images.com/sZYp_3BTDGjh2unaZfZmuA__thumb/img/example1.jpg", games[0].thumbnail_url.?);
    try std.testing.expectEqual(@as(?i32, 2018), games[0].year_published);

    try std.testing.expectEqual(@as(u32, 291457), games[4].id);
    try std.testing.expectEqual(@as(u32, 5), games[4].rank);
    try std.testing.expectEqualStrings("Gloomhaven: Jaws of the Lion", games[4].name);
    try std.testing.expectEqualStrings("https://cf.geekdo-images.com/example5__thumb/img/example5.jpg", games[4].thumbnail_url.?);
    try std.testing.expectEqual(@as(?i32, 2020), games[4].year_published);
}

test "parse thing XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.thing),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const games = try parseThingResponse(std.testing.allocator, bytes);
    defer freeGames(std.testing.allocator, games);

    try std.testing.expectEqual(@as(usize, 1), games.len);

    const game = games[0];
    try std.testing.expectEqual(@as(u32, 13), game.id);
    try std.testing.expectEqualStrings("CATAN", game.name);
    try std.testing.expectEqual(@as(?i32, 1995), game.year_published);
    try std.testing.expect(game.description.len > 0);
    try std.testing.expect(game.thumbnail_url != null);
    try std.testing.expect(game.image_url != null);

    try std.testing.expectEqual(@as(u32, 3), game.min_players);
    try std.testing.expectEqual(@as(u32, 4), game.max_players);
    try std.testing.expectEqual(@as(u32, 120), game.playing_time);
    try std.testing.expectEqual(@as(u32, 60), game.min_play_time);
    try std.testing.expectEqual(@as(u32, 120), game.max_play_time);
    try std.testing.expectEqual(@as(u32, 10), game.min_age);

    try std.testing.expectApproxEqAbs(@as(f64, 7.14567), game.rating, 0.00001);
    try std.testing.expectEqual(@as(u32, 98765), game.users_rated);
    try std.testing.expectApproxEqAbs(@as(f64, 7.01234), game.bayes_average, 0.00001);
    try std.testing.expectEqual(@as(u32, 389), game.rank);
    try std.testing.expectApproxEqAbs(@as(f64, 2.32), game.weight, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.54321), game.stddev, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), game.median, 0.00001);
    try std.testing.expectEqual(@as(u32, 123456), game.owned);
    try std.testing.expectEqual(@as(u32, 23456), game.num_comments);
    try std.testing.expectEqual(@as(u32, 7890), game.num_weights);

    try std.testing.expectEqual(@as(usize, 1), game.designers.len);
    try std.testing.expectEqualStrings("Klaus Teuber", game.designers[0]);
    try std.testing.expectEqual(@as(usize, 2), game.artists.len);
    try std.testing.expectEqualStrings("Volkan Baga", game.artists[0]);
    try std.testing.expectEqualStrings("Tanja Donner", game.artists[1]);
    try std.testing.expectEqual(@as(usize, 2), game.categories.len);
    try std.testing.expectEqual(@as(usize, 4), game.mechanics.len);
    try std.testing.expectEqual(@as(usize, 2), game.publishers.len);

    const poll = game.player_count_poll.?;
    try std.testing.expectEqual(@as(u32, 2551), poll.total_votes);
    try std.testing.expectEqual(@as(usize, 5), poll.results.len);
    try std.testing.expectEqualStrings("4", poll.results[3].num_players);
    try std.testing.expectEqual(@as(u32, 1838), poll.results[3].best);
    try std.testing.expectEqual(@as(u32, 525), poll.results[3].recommended);
    try std.testing.expectEqual(@as(u32, 52), poll.results[3].not_recommended);
    try std.testing.expectEqualStrings("Best with 4 players", poll.best_with.?);
    try std.testing.expectEqualStrings("Recommended with 3-4 players", poll.recommended_with.?);
}

test "parse collection XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.collection),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const items = try parseCollectionResponse(std.testing.allocator, bytes);
    defer freeCollectionItems(std.testing.allocator, items);

    try std.testing.expectEqual(@as(usize, 3), items.len);

    try std.testing.expectEqual(@as(u32, 13), items[0].id);
    try std.testing.expectEqualStrings("CATAN", items[0].name);
    try std.testing.expectEqual(@as(?i32, 1995), items[0].year_published);
    try std.testing.expect(items[0].image_url != null);
    try std.testing.expect(items[0].thumbnail_url != null);
    try std.testing.expectEqual(@as(u32, 25), items[0].num_plays);
    try std.testing.expect(items[0].owned);
    try std.testing.expect(!items[0].prev_owned);
    try std.testing.expect(!items[0].for_trade);
    try std.testing.expect(!items[0].want);
    try std.testing.expect(items[0].want_to_play);
    try std.testing.expect(!items[0].want_to_buy);
    try std.testing.expect(!items[0].wishlist);
    try std.testing.expect(!items[0].preordered);
    try std.testing.expectApproxEqAbs(@as(f64, 8), items[0].rating, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.14), items[0].bgg_rating, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f64, 7.01), items[0].bayes_average, 0.00001);
    try std.testing.expectEqual(@as(u32, 42), items[0].rank);

    try std.testing.expectEqual(@as(u32, 224517), items[2].id);
    try std.testing.expectEqualStrings("Brass: Birmingham", items[2].name);
    try std.testing.expect(!items[2].owned);
    try std.testing.expect(items[2].wishlist);
    try std.testing.expectApproxEqAbs(@as(f64, 0), items[2].rating, 0.00001);
    try std.testing.expectEqual(@as(u32, 0), items[2].rank);
}

test "parse forum list XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.forum_list),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const forums = try parseForumListResponse(std.testing.allocator, bytes);
    defer freeForums(std.testing.allocator, forums);

    try std.testing.expectEqual(@as(usize, 3), forums.len);

    try std.testing.expectEqual(@as(u32, 19), forums[0].id);
    try std.testing.expectEqualStrings("Reviews", forums[0].title);
    try std.testing.expectEqualStrings("Post your game reviews in this forum.", forums[0].description);
    try std.testing.expectEqual(@as(u32, 150), forums[0].num_threads);
    try std.testing.expectEqual(@as(u32, 450), forums[0].num_posts);
    try std.testing.expectEqualStrings("Sat, 01 Jan 2025 10:00:00 +0000", forums[0].last_post_date);

    try std.testing.expectEqual(@as(u32, 21), forums[2].id);
    try std.testing.expectEqualStrings("General", forums[2].title);
    try std.testing.expectEqual(@as(u32, 500), forums[2].num_threads);
    try std.testing.expectEqual(@as(u32, 2500), forums[2].num_posts);
}
