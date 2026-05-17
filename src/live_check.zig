const std = @import("std");
const bgg_tui = @import("bgg_tui");

const LiveCheckError = error{
    MissingConfigDirectory,
    MissingApiToken,
    ApiRequestFailed,
    ApiParseFailed,
    EmptyHotList,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    // Keep live API access explicit. The normal app scaffold can run without
    // touching the network, while this build step verifies the real configured
    // token and parser path end-to-end.
    const config_path = bgg_tui.config.resolveConfigPath(allocator, init.environ_map) catch |err| switch (err) {
        error.MissingConfigDirectory => return LiveCheckError.MissingConfigDirectory,
        else => return err,
    };
    defer allocator.free(config_path);

    var loaded_config = try bgg_tui.config.loadConfig(allocator, init.io, config_path, init.environ_map);
    defer loaded_config.deinit(allocator);

    // Do not print the token. The check only reports whether a real BGG request
    // succeeds and whether the XML response can be parsed.
    const token = loaded_config.config.apiClientToken() orelse return LiveCheckError.MissingApiToken;

    var client = bgg_tui.bgg.client.Client.init(allocator, init.io, .{ .token = token });
    defer client.deinit();

    const hot_path = try bgg_tui.bgg.endpoint.hot(allocator);
    defer allocator.free(hot_path);

    const result = try client.getPath(hot_path, .generic);
    const response = switch (result) {
        .ok => |response| response,
        .api_error => |err| {
            std.debug.print("BGG live API check failed: {s}\n", .{@tagName(err.kind())});
            return LiveCheckError.ApiRequestFailed;
        },
    };
    defer response.deinit(allocator);

    const games = bgg_tui.bgg.xml.parseHotResponse(allocator, response.body) catch |parse_error| switch (parse_error) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const err = bgg_tui.bgg.err.classifyParseError(parse_error);
            std.debug.print("BGG live API check failed: {s}: {s}\n", .{ @tagName(err.kind()), err.parse.message });
            return LiveCheckError.ApiParseFailed;
        },
    };
    defer bgg_tui.bgg.xml.freeHotGames(allocator, games);

    if (games.len == 0) return LiveCheckError.EmptyHotList;

    std.debug.print("BGG live API check passed: hot games={d}, first=\"{s}\"\n", .{ games.len, games[0].name });
}
