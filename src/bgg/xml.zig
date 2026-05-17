const std = @import("std");
const xml_lib = @import("xml");

const html = @import("html.zig");
const model = @import("model.zig");

const Allocator = std.mem.Allocator;

/// Domain parse failures produced after the XML stream itself was readable.
///
/// Allocation and low-level XML reader errors are returned directly by the parse
/// functions. Callers can use `bgg.err.classifyParseError` when they need to map
/// these failures into API-level error reporting.
pub const ParseError = error{
    MissingRequiredAttribute,
    MissingName,
    MissingPrimaryName,
    UnexpectedEndOfDocument,
    UnexpectedElementEnd,
};

/// Fixture files kept from the Go implementation and reused by Zig parser tests.
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

/// Parses the BGG search endpoint response.
///
/// Returned result names are allocator-owned. Release the slice with
/// `freeSearchResults` using the same allocator.
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

/// Parses the BGG hot endpoint response.
///
/// Returned strings are allocator-owned. Release the slice with `freeHotGames`
/// using the same allocator.
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

/// Parses the BGG thing endpoint response into detailed game models.
///
/// Text fields, link lists, and player poll strings are allocator-owned. Release
/// the slice with `freeGames` using the same allocator.
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

/// Parses the BGG collection endpoint response.
///
/// Returned string fields are allocator-owned. Release the slice with
/// `freeCollectionItems` using the same allocator.
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

/// Parses a forum list response for one game.
///
/// Returned forum strings are allocator-owned. Release the slice with
/// `freeForums` using the same allocator.
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

/// Parses a forum page response into thread summaries.
///
/// BGG forum responses do not carry the requested page in the XML payload, so
/// the caller-provided `page` is copied into the returned model. Use
/// `freeThreadList` to release the returned thread summary slice.
pub fn parseForumResponse(allocator: Allocator, bytes: []const u8, page: u32) !model.ThreadList {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "forum")) {
                    return try parseForumPage(allocator, reader, if (page == 0) 1 else page);
                }
                try reader.skipElement();
            },
            .element_end => return ParseError.UnexpectedElementEnd,
        }
    }
}

/// Parses a thread response, including article bodies.
///
/// Article bodies are decoded for HTML entities but are still HTML-ish text until
/// `bgg.html.toText` is applied by the display layer. Use `freeThread` to release
/// the returned thread.
pub fn parseThreadResponse(allocator: Allocator, bytes: []const u8) !model.Thread {
    var static_reader: xml_lib.Reader.Static = .init(allocator, bytes, .{});
    defer static_reader.deinit();
    const reader = &static_reader.interface;

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration, .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "thread")) {
                    return try parseThread(allocator, reader);
                }
                try reader.skipElement();
            },
            .element_end => return ParseError.UnexpectedElementEnd,
        }
    }
}

/// Frees a search result slice returned by `parseSearchResponse`.
pub fn freeSearchResults(allocator: Allocator, results: []model.GameSearchResult) void {
    for (results) |item| {
        allocator.free(item.name);
    }
    allocator.free(results);
}

/// Frees a hot game slice returned by `parseHotResponse`.
pub fn freeHotGames(allocator: Allocator, games: []model.HotGame) void {
    freeHotGameItems(allocator, games);
    allocator.free(games);
}

/// Frees a game slice returned by `parseThingResponse`.
pub fn freeGames(allocator: Allocator, games: []model.Game) void {
    freeGameItems(allocator, games);
    allocator.free(games);
}

/// Frees a collection item slice returned by `parseCollectionResponse`.
pub fn freeCollectionItems(allocator: Allocator, items: []model.CollectionItem) void {
    freeCollectionItemsOnly(allocator, items);
    allocator.free(items);
}

/// Frees a forum slice returned by `parseForumListResponse`.
pub fn freeForums(allocator: Allocator, forums: []model.Forum) void {
    freeForumItems(allocator, forums);
    allocator.free(forums);
}

/// Frees a thread list returned by `parseForumResponse`.
pub fn freeThreadList(allocator: Allocator, thread_list: model.ThreadList) void {
    freeThreadSummaries(allocator, thread_list.threads);
}

/// Frees a thread returned by `parseThreadResponse`.
pub fn freeThread(allocator: Allocator, thread: model.Thread) void {
    allocator.free(thread.subject);
    freeArticles(allocator, thread.articles);
}

fn parseSearchItem(allocator: Allocator, reader: *xml_lib.Reader) !model.GameSearchResult {
    const id = try parseU32Attribute(reader, "id");

    var name: ?[]const u8 = null;
    var fallback_name: ?[]const u8 = null;
    errdefer if (name) |value| allocator.free(value);
    errdefer if (fallback_name) |value| allocator.free(value);

    var year_published: ?i32 = null;

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "name")) {
                    const is_primary = isAttributeValue(reader, "type", "primary");
                    if (is_primary) {
                        if (name) |old| allocator.free(old);
                        name = try dupeAttributeValue(allocator, reader, "value");
                    } else if (fallback_name == null) {
                        fallback_name = try dupeAttributeValue(allocator, reader, "value");
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
                    const resolved_name = if (name) |primary| blk: {
                        if (fallback_name) |fallback| allocator.free(fallback);
                        break :blk primary;
                    } else fallback_name orelse return ParseError.MissingPrimaryName;
                    name = null;
                    fallback_name = null;
                    return .{
                        .id = id,
                        .name = resolved_name,
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
                    replaceRequiredString(allocator, &builder.game.description, try readDecodedElementText(allocator, reader));
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

fn parseForumPage(allocator: Allocator, reader: *xml_lib.Reader, page: u32) !model.ThreadList {
    const num_threads = try parseU32Attribute(reader, "numthreads");
    var thread_list: model.ThreadList = .{
        .page = page,
        .total_pages = totalPages(num_threads, 50),
    };
    errdefer freeThreadList(allocator, thread_list);

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "threads")) {
                    thread_list.threads = try parseThreadSummaries(allocator, reader);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "forum")) return thread_list;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseThreadSummaries(allocator: Allocator, reader: *xml_lib.Reader) ![]model.ThreadSummary {
    var threads: std.ArrayList(model.ThreadSummary) = .empty;
    errdefer {
        freeThreadSummaryItems(allocator, threads.items);
        threads.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "thread")) {
                    try threads.append(allocator, try parseThreadSummary(allocator, reader));
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "threads")) return try threads.toOwnedSlice(allocator);
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseThreadSummary(allocator: Allocator, reader: *xml_lib.Reader) !model.ThreadSummary {
    const thread: model.ThreadSummary = .{
        .id = try parseU32Attribute(reader, "id"),
        .subject = try dupeAttributeValue(allocator, reader, "subject"),
        .author = try dupeAttributeValue(allocator, reader, "author"),
        .num_articles = try parseU32Attribute(reader, "numarticles"),
        .post_date = try dupeAttributeValue(allocator, reader, "postdate"),
        .last_post_date = try dupeAttributeValue(allocator, reader, "lastpostdate"),
    };
    errdefer freeThreadSummary(allocator, thread);

    try reader.skipElement();
    return thread;
}

fn parseThread(allocator: Allocator, reader: *xml_lib.Reader) !model.Thread {
    var thread: model.Thread = .{
        .id = try parseU32Attribute(reader, "id"),
        .subject = "",
    };
    errdefer freeThread(allocator, thread);

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "subject")) {
                    replaceRequiredString(allocator, &thread.subject, try reader.readElementTextAlloc(allocator));
                } else if (std.mem.eql(u8, reader.elementName(), "articles")) {
                    thread.articles = try parseArticles(allocator, reader);
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "thread")) {
                    if (thread.subject.len == 0) return ParseError.MissingName;
                    return thread;
                }
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseArticles(allocator: Allocator, reader: *xml_lib.Reader) ![]model.Article {
    var articles: std.ArrayList(model.Article) = .empty;
    errdefer {
        freeArticleItems(allocator, articles.items);
        articles.deinit(allocator);
    }

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "article")) {
                    try articles.append(allocator, try parseArticle(allocator, reader));
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "articles")) return try articles.toOwnedSlice(allocator);
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
}

fn parseArticle(allocator: Allocator, reader: *xml_lib.Reader) !model.Article {
    var article: model.Article = .{
        .id = try parseU32Attribute(reader, "id"),
        .username = try dupeAttributeValue(allocator, reader, "username"),
        .post_date = try dupeAttributeValue(allocator, reader, "postdate"),
    };
    errdefer freeArticle(allocator, article);

    while (true) {
        const node = try reader.read();
        switch (node) {
            .eof => return ParseError.UnexpectedEndOfDocument,
            .xml_declaration => unreachable,
            .comment, .pi, .text, .cdata, .character_reference, .entity_reference => continue,
            .element_start => {
                if (std.mem.eql(u8, reader.elementName(), "body")) {
                    replaceRequiredString(allocator, &article.body, try readDecodedElementText(allocator, reader));
                } else {
                    try reader.skipElement();
                }
            },
            .element_end => {
                if (std.mem.eql(u8, reader.elementName(), "article")) return article;
                return ParseError.UnexpectedElementEnd;
            },
        }
    }
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

    /// Transfers accumulated link arrays into the game.
    ///
    /// After success, the returned `model.Game` owns the slices and must be
    /// released with `freeGame` / `freeGames`; the builder must not be used.
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

fn freeThreadSummaries(allocator: Allocator, threads: []model.ThreadSummary) void {
    freeThreadSummaryItems(allocator, threads);
    allocator.free(threads);
}

fn freeThreadSummaryItems(allocator: Allocator, threads: []model.ThreadSummary) void {
    for (threads) |thread| {
        freeThreadSummary(allocator, thread);
    }
}

fn freeThreadSummary(allocator: Allocator, thread: model.ThreadSummary) void {
    allocator.free(thread.subject);
    allocator.free(thread.author);
    if (thread.post_date.len > 0) allocator.free(thread.post_date);
    if (thread.last_post_date.len > 0) allocator.free(thread.last_post_date);
}

fn freeArticles(allocator: Allocator, articles: []model.Article) void {
    freeArticleItems(allocator, articles);
    allocator.free(articles);
}

fn freeArticleItems(allocator: Allocator, articles: []model.Article) void {
    for (articles) |article| {
        freeArticle(allocator, article);
    }
}

fn freeArticle(allocator: Allocator, article: model.Article) void {
    allocator.free(article.username);
    if (article.post_date.len > 0) allocator.free(article.post_date);
    if (article.body.len > 0) allocator.free(article.body);
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

fn totalPages(total_items: u32, page_size: u32) u32 {
    if (total_items == 0) return 1;
    return (total_items + page_size - 1) / page_size;
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

// BGG often double-escapes rich text through XML, for example `&amp;#10;`.
// The XML reader decodes the outer XML entity first; this helper decodes the
// remaining HTML entity layer before storing description/body text in models.
fn readDecodedElementText(allocator: Allocator, reader: *xml_lib.Reader) ![]u8 {
    const raw = try reader.readElementTextAlloc(allocator);
    defer allocator.free(raw);
    return try html.decodeEntities(allocator, raw);
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

test "parse search XML with escaped apostrophe in name attribute" {
    const bytes =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<items total="1" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
        \\  <item type="boardgame" id="438388">
        \\    <name type="primary" value="Paupers&#039; Ladder: The Rootwings"/>
        \\  </item>
        \\</items>
    ;

    const results = try parseSearchResponse(std.testing.allocator, bytes);
    defer freeSearchResults(std.testing.allocator, results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Paupers' Ladder: The Rootwings", results[0].name);
}

test "parse search XML falls back to first name when primary name is missing" {
    const bytes =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<items total="1" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
        \\  <item type="boardgame" id="6492">
        \\    <name type="alternate" value="Rootbound"/>
        \\  </item>
        \\</items>
    ;

    const results = try parseSearchResponse(std.testing.allocator, bytes);
    defer freeSearchResults(std.testing.allocator, results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Rootbound", results[0].name);
}

test "parse search XML prefers primary name over alternate name" {
    const bytes =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<items total="1" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
        \\  <item type="boardgame" id="237182">
        \\    <name type="alternate" value="Racine"/>
        \\    <name type="primary" value="Root"/>
        \\  </item>
        \\</items>
    ;

    const results = try parseSearchResponse(std.testing.allocator, bytes);
    defer freeSearchResults(std.testing.allocator, results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Root", results[0].name);
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
    try std.testing.expect(std.mem.indexOf(u8, game.description, "\n\nSetup includes") != null);
    try std.testing.expect(std.mem.indexOf(u8, game.description, "&#10;") == null);
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

test "parse forum threads XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.forum),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const thread_list = try parseForumResponse(std.testing.allocator, bytes, 1);
    defer freeThreadList(std.testing.allocator, thread_list);

    try std.testing.expectEqual(@as(u32, 1), thread_list.page);
    try std.testing.expectEqual(@as(u32, 3), thread_list.total_pages);
    try std.testing.expectEqual(@as(usize, 3), thread_list.threads.len);

    try std.testing.expectEqual(@as(u32, 1001), thread_list.threads[0].id);
    try std.testing.expectEqualStrings("Best strategy for beginners?", thread_list.threads[0].subject);
    try std.testing.expectEqualStrings("player1", thread_list.threads[0].author);
    try std.testing.expectEqual(@as(u32, 15), thread_list.threads[0].num_articles);
    try std.testing.expectEqualStrings("Mon, 25 Dec 2024 08:00:00 +0000", thread_list.threads[0].post_date);
    try std.testing.expectEqualStrings("Sat, 01 Jan 2025 12:00:00 +0000", thread_list.threads[0].last_post_date);

    try std.testing.expectEqual(@as(u32, 1003), thread_list.threads[2].id);
    try std.testing.expectEqualStrings("Component quality issues", thread_list.threads[2].subject);
    try std.testing.expectEqualStrings("collector99", thread_list.threads[2].author);
    try std.testing.expectEqual(@as(u32, 25), thread_list.threads[2].num_articles);
}

test "parse thread XML fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        Fixture.path(.thread),
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(bytes);

    const thread = try parseThreadResponse(std.testing.allocator, bytes);
    defer freeThread(std.testing.allocator, thread);

    try std.testing.expectEqual(@as(u32, 1001), thread.id);
    try std.testing.expectEqualStrings("Best strategy for beginners?", thread.subject);
    try std.testing.expectEqual(@as(usize, 3), thread.articles.len);

    try std.testing.expectEqual(@as(u32, 5001), thread.articles[0].id);
    try std.testing.expectEqualStrings("player1", thread.articles[0].username);
    try std.testing.expectEqualStrings("Mon, 25 Dec 2024 08:00:00 +0000", thread.articles[0].post_date);
    try std.testing.expect(std.mem.indexOf(u8, thread.articles[0].body, "I'm looking") != null);

    try std.testing.expectEqual(@as(u32, 5002), thread.articles[1].id);
    try std.testing.expectEqualStrings("expert_gamer", thread.articles[1].username);
    try std.testing.expect(std.mem.indexOf(u8, thread.articles[1].body, "Don't spread") != null);
    try std.testing.expect(std.mem.indexOf(u8, thread.articles[1].body, "Good luck & have fun!") != null);

    try std.testing.expectEqual(@as(u32, 5003), thread.articles[2].id);
    try std.testing.expectEqualStrings("player1", thread.articles[2].username);
    try std.testing.expect(std.mem.endsWith(u8, thread.articles[2].body, "next game."));
}
