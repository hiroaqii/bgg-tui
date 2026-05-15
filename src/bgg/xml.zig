const std = @import("std");
const xml_lib = @import("xml");

const model = @import("model.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    MissingRequiredAttribute,
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

pub fn freeSearchResults(allocator: Allocator, results: []model.GameSearchResult) void {
    for (results) |item| {
        allocator.free(item.name);
    }
    allocator.free(results);
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

fn parseU32Attribute(reader: *xml_lib.Reader, name: []const u8) !u32 {
    const value = try attributeValue(reader, name);
    return std.fmt.parseInt(u32, value, 10);
}

fn parseI32Attribute(reader: *xml_lib.Reader, name: []const u8) !i32 {
    const value = try attributeValue(reader, name);
    return std.fmt.parseInt(i32, value, 10);
}

fn dupeAttributeValue(allocator: Allocator, reader: *xml_lib.Reader, name: []const u8) ![]const u8 {
    const index = reader.attributeIndex(name) orelse return ParseError.MissingRequiredAttribute;
    return try reader.attributeValueAlloc(allocator, index);
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
