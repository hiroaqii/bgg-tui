const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_client = @import("bgg/client.zig");
const bgg_endpoint = @import("bgg/endpoint.zig");
const bgg_error = @import("bgg/error.zig");
const bgg_model = @import("bgg/model.zig");
const bgg_xml = @import("bgg/xml.zig");
const config_mod = @import("config.zig");

// Keep top-level screens centered until a screen needs its own full-page layout.
const main_menu_size = chasen.Size{ .width = 48, .height = 12 };
const setup_token_size = chasen.Size{ .width = 56, .height = 9 };
const placeholder_size = chasen.Size{ .width = 56, .height = 6 };
const hot_list_size = chasen.Size{ .width = 72, .height = 18 };

const menu_items = [_]ui.Menu.Item{
    .{ .label = "Hot Games", .shortcut = "h" },
    .{ .label = "Search Games", .shortcut = "/" },
    .{ .label = "Collection", .shortcut = "c" },
    .{ .label = "Settings", .shortcut = "s" },
};

pub const Screen = enum {
    setup_token,
    main_menu,
    hot_games,
    search,
    collection,
    settings,
};

pub const App = struct {
    config: config_mod.Config,
    config_path: ?[]const u8 = null,
    screen: Screen,
    allocator: ?std.mem.Allocator = null,
    setup_token_input: ?ui.PasswordInput = null,
    owned_token: ?[]u8 = null,
    hot_games: HotGamesState = .{},
    menu: ui.Menu = ui.Menu.init(.{ .items = &menu_items }),
    shell: ui.Panel = ui.Panel.init(.{}),

    pub const Msg = union(enum) {
        setup_token_input: ui.PasswordInput.Msg,
        setup_token_paste: []const u8,
        menu: ui.Menu.Msg,
        hot_list: ui.List.Msg,
        hot_games_loaded: HotGamesResult,
        show_screen: Screen,
        quit,
    };

    pub const Options = struct {
        config_path: ?[]const u8 = null,
    };

    pub fn create(config: config_mod.Config, options: Options) App {
        return .{
            .config = config,
            .config_path = options.config_path,
            .screen = if (config.apiClientToken() == null) .setup_token else .main_menu,
        };
    }

    pub fn init(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.allocator = ctx.allocator();
        self.setup_token_input = try ui.PasswordInput.init(ctx.allocator(), .{
            .placeholder = "Paste BGG API token",
        });
    }

    pub fn update(self: *App, msg: Msg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .setup_token_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitToken(ctx);
                } else if (self.setup_token_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .setup_token_paste => |text| {
                if (self.setup_token_input) |*input| {
                    try insertPastedToken(input, text);
                }
            },
            .menu => |menu_msg| switch (menu_msg) {
                .move_prev, .move_next => self.menu.update(menu_msg),
                .activate => |index| {
                    if (screenForMenuIndex(index)) |screen| try self.showScreen(screen, ctx);
                },
            },
            .hot_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.hot_games.update(list_msg),
                .activate => {},
            },
            .hot_games_loaded => |result| try self.finishHotGamesLoad(result),
            .show_screen => |screen| try self.showScreen(screen, ctx),
            .quit => {
                self.deinitOwnedState();
                ctx.quit();
            },
        }
    }

    pub fn view(self: *const App, sfc: *chasen.Surface) !void {
        const size = sfc.size();
        if (size.width == 0 or size.height == 0) return;

        // Reserve the last row for global status; screens render inside the panel body.
        const status_row = if (size.height > 0) size.height - 1 else 0;
        var shell_area = sfc.child(.{
            .col = 0,
            .row = 0,
            .width = size.width,
            .height = status_row,
        });
        self.shell.view(&shell_area, .{
            .title = "BoardGameGeek",
            .border = .rounded,
        });

        var body_area = shell_area.child(ui.Panel.contentRect(&shell_area, .{}));
        try self.viewCurrentScreen(&body_area);

        var status_area = sfc.child(.{
            .col = 0,
            .row = status_row,
            .width = size.width,
            .height = 1,
        });
        const status = ui.StatusLine.init(.{
            .left = "bgg-tui",
            .center = screenTitle(self.screen),
            .right = statusRightHint(self.screen),
        });
        status.view(&status_area, .{});
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        if (self.screen == .setup_token) {
            switch (event) {
                .key_press => |key| if (key.matches(chasen.Key.escape, .{})) return .quit,
                .paste => |text| return .{ .setup_token_paste = text },
                else => {},
            }
            if (self.setup_token_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .setup_token_input = msg };
            }
            return null;
        }

        switch (event) {
            .key_press => |key| {
                // Global shortcuts get first chance before screen-local handlers.
                if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'q') return .quit;
                if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                if (key.codepoint == 'h') return .{ .show_screen = .hot_games };
                if (key.codepoint == '/') return .{ .show_screen = .search };
                if (key.codepoint == 'c') return .{ .show_screen = .collection };
                if (key.codepoint == 's') return .{ .show_screen = .settings };
            },
            else => {},
        }

        if (self.screen == .main_menu) {
            // Menu owns only cursor movement and activation; App maps activation to screens.
            if (self.menu.handleEvent(event)) |msg| return .{ .menu = msg };
        }
        if (self.screen == .hot_games) {
            if (self.hot_games.handleEvent(event)) |msg| return .{ .hot_list = msg };
        }
        return null;
    }

    fn viewCurrentScreen(self: *const App, sfc: *chasen.Surface) !void {
        switch (self.screen) {
            .setup_token => self.viewSetupToken(sfc),
            .main_menu => try self.viewMainMenu(sfc),
            .hot_games => self.viewHotGames(sfc),
            .search => self.viewPlaceholder(sfc, "Search Games", "Search input and results are pending."),
            .collection => self.viewPlaceholder(sfc, "Collection", "Collection loading is planned after the MVP list flow."),
            .settings => self.viewPlaceholder(sfc, "Settings", "Minimum settings screen is pending."),
        }
    }

    fn viewSetupToken(self: *const App, sfc: *chasen.Surface) void {
        var area = centeredSurface(sfc, setup_token_size);
        _ = area.textAt(0, 0, "Setup BGG API token", .{ .bold = true, .fg = .{ .index = 14 } });
        _ = area.textAt(0, 2, "BGG API access requires a token.", .{ .fg = .gray });
        _ = area.textAt(0, 3, "Enter a token to continue to the main menu.", .{ .fg = .gray });

        if (self.setup_token_input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 5, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        _ = area.textAt(0, 7, setupTokenSubmitHint(self.config_path), .{ .dim = true });
    }

    fn viewMainMenu(self: *const App, sfc: *chasen.Surface) !void {
        var area = centeredSurface(sfc, main_menu_size);
        const token_status = if (self.config.apiClientToken() == null) "missing" else "configured";
        _ = area.textAt(0, 0, "Main menu", .{ .bold = true });
        _ = try area.printAt(0, 2, .{ .fg = .gray }, "BGG API token: {s}", .{token_status});

        var menu_area = area.child(.{
            .col = 0,
            .row = 4,
            .width = @min(area.size().width, 36),
            .height = @min(area.size().height -| 4, @as(u16, menu_items.len)),
        });
        self.menu.view(&menu_area, .{
            .shortcut_col = 24,
            .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
        });

        _ = area.textAt(0, 10, "Use Up/Down and Enter, or h, /, c, s shortcuts.", .{ .dim = true });
    }

    fn viewPlaceholder(self: *const App, sfc: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        var area = centeredSurface(sfc, placeholder_size);
        _ = area.textAt(0, 0, title, .{ .bold = true, .fg = .{ .index = 14 } });
        _ = area.textAt(0, 2, message, .{ .fg = .gray });
        _ = area.textAt(0, 4, "m: menu  Esc/q: quit", .{ .dim = true });
    }

    fn viewHotGames(self: *const App, sfc: *chasen.Surface) void {
        var area = centeredSurface(sfc, hot_list_size);
        _ = area.textAt(0, 0, "Hot Games", .{ .bold = true, .fg = .{ .index = 14 } });

        switch (self.hot_games.load_state) {
            .idle, .loading => {
                _ = area.textAt(0, 2, "Loading BoardGameGeek hot games...", .{ .fg = .gray });
            },
            .failed => |message| {
                _ = area.textAt(0, 2, "Could not load hot games.", .{ .fg = .{ .index = 9 } });
                _ = area.textAt(0, 4, message, .{ .fg = .gray });
            },
            .loaded => {
                if (self.hot_games.list.items.len == 0) {
                    _ = area.textAt(0, 2, "No hot games returned by BGG.", .{ .fg = .gray });
                } else {
                    var list_area = area.child(.{
                        .col = 0,
                        .row = 2,
                        .width = area.size().width,
                        .height = area.size().height -| 4,
                    });
                    self.hot_games.list.view(&list_area, .{
                        .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
                    });
                }
            },
        }

        _ = area.textAt(0, area.size().height -| 1, "Up/Down: move  m: menu  Esc/q: quit", .{ .dim = true });
    }

    fn submitToken(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.setup_token_input) |*input| input else return;
        const token = std.mem.trim(u8, input.text(), " \t\r\n");
        if (token.len == 0) return;

        if (self.owned_token) |old| self.allocator.?.free(old);
        self.owned_token = try self.allocator.?.dupe(u8, token);
        self.config.api.token = self.owned_token;
        // Persist only after the token is owned by App so config can safely
        // borrow the value for both this session and TOML serialization.
        if (self.config_path) |path| {
            try config_mod.saveConfig(ctx.allocator(), ctx.io(), path, self.config);
        }
        try input.update(.clear);
        self.screen = .main_menu;
    }

    fn deinitOwnedState(self: *App) void {
        if (self.setup_token_input) |*input| {
            input.deinit();
            self.setup_token_input = null;
        }
        if (self.owned_token) |token| {
            self.allocator.?.free(token);
            self.owned_token = null;
        }
        self.hot_games.deinit(self.allocator.?);
    }

    fn showScreen(self: *App, screen: Screen, ctx: *chasen.Ctx(Msg)) !void {
        self.screen = screen;
        if (screen == .hot_games) {
            try self.startHotGamesLoad(ctx);
        }
    }

    fn startHotGamesLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.hot_games.load_state == .loading or self.hot_games.load_state == .loaded) return;

        const token = self.config.apiClientToken() orelse {
            self.hot_games.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(HotGamesTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{ .token = try ctx.allocator().dupe(u8, token) };
        errdefer ctx.allocator().free(task.token);

        self.hot_games.setLoading();
        ctx.spawnWith(task, HotGamesTask.run) catch |err| {
            self.hot_games.setFailed("Could not start hot games loading task");
            return err;
        };
    }

    fn finishHotGamesLoad(self: *App, result: HotGamesResult) !void {
        switch (result) {
            .ok => |games| try self.hot_games.setLoaded(self.allocator.?, games),
            .failed => |message| self.hot_games.setFailed(message),
        }
    }
};

const HotGamesState = struct {
    load_state: LoadState = .idle,
    games: []bgg_model.HotGame = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),

    const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    fn setLoading(self: *HotGamesState) void {
        self.load_state = .loading;
    }

    fn setFailed(self: *HotGamesState, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    fn setLoaded(self: *HotGamesState, allocator: std.mem.Allocator, games: []bgg_model.HotGame) !void {
        self.deinit(allocator);
        self.games = games;
        self.labels = try buildHotGameLabels(allocator, games);
        self.list = ui.List.init(.{ .items = self.labels });
        self.load_state = .loaded;
    }

    fn update(self: *HotGamesState, msg: ui.List.Msg) void {
        self.list.update(msg);
    }

    fn handleEvent(self: *const HotGamesState, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        return self.list.handleEvent(event);
    }

    fn deinit(self: *HotGamesState, allocator: std.mem.Allocator) void {
        freeHotGameLabels(allocator, self.labels);
        bgg_xml.freeHotGames(allocator, self.games);
        self.labels = &.{};
        self.games = &.{};
        self.list = ui.List.init(.{});
        self.load_state = .idle;
    }
};

const HotGamesResult = union(enum) {
    ok: []bgg_model.HotGame,
    failed: []const u8,
};

// The task owns only copied request inputs. API response data is transferred
// back to App through the result message and released with the app state.
const HotGamesTask = struct {
    token: []const u8,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *HotGamesTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.destroy(task);
        }

        return .{ .hot_games_loaded = loadHotGames(allocator, io, task.token) catch |err| .{ .failed = @errorName(err) } };
    }
};

fn loadHotGames(allocator: std.mem.Allocator, io: std.Io, token: []const u8) !HotGamesResult {
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

fn apiErrorMessage(err: bgg_error.ApiError) []const u8 {
    return switch (err) {
        .auth => |auth| auth.message,
        .rate_limit => |rate_limit| rate_limit.message,
        .not_found => "BGG API resource was not found",
        .network => |network| network.message,
        .parse => |parse| parse.message,
    };
}

fn buildHotGameLabels(allocator: std.mem.Allocator, games: []const bgg_model.HotGame) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, games.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    for (games, 0..) |game, index| {
        labels[index] = try formatHotGameLabel(allocator, game);
        initialized_count = index + 1;
    }

    return labels;
}

fn formatHotGameLabel(allocator: std.mem.Allocator, game: bgg_model.HotGame) ![]u8 {
    if (game.year_published) |year| {
        return try std.fmt.allocPrint(allocator, "#{d: >2}  {s} ({d})", .{ game.rank, game.name, year });
    }
    return try std.fmt.allocPrint(allocator, "#{d: >2}  {s}", .{ game.rank, game.name });
}

fn freeHotGameLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

// App screens receive a local surface. `ui.layout.center` handles clamping when
// the terminal is smaller than the requested block.
fn centeredSurface(surface: *chasen.Surface, size: chasen.Size) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), size));
}

fn surfaceRect(surface: *const chasen.Surface) chasen.Rect {
    const size = surface.size();
    return .{ .col = 0, .row = 0, .width = size.width, .height = size.height };
}

fn screenForMenuIndex(index: usize) ?Screen {
    return switch (index) {
        0 => .hot_games,
        1 => .search,
        2 => .collection,
        3 => .settings,
        else => null,
    };
}

fn screenTitle(screen: Screen) []const u8 {
    return switch (screen) {
        .setup_token => "setup token",
        .main_menu => "main menu",
        .hot_games => "hot games",
        .search => "search",
        .collection => "collection",
        .settings => "settings",
    };
}

fn statusRightHint(screen: Screen) []const u8 {
    return switch (screen) {
        .setup_token => "Esc: quit",
        else => "m: menu  Esc/q: quit",
    };
}

fn insertPastedToken(input: *ui.PasswordInput, text: []const u8) !void {
    var index: usize = 0;
    while (index < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[index]) catch {
            index += 1;
            continue;
        };
        if (index + len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[index .. index + len]) catch {
            index += len;
            continue;
        };
        if (isPasteCodepoint(codepoint)) {
            try input.update(.{ .insert = codepoint });
        }
        index += len;
    }
}

fn isPasteCodepoint(codepoint: u21) bool {
    return codepoint >= 0x20 and codepoint != 0x7f and !(codepoint >= 0x80 and codepoint <= 0x9f);
}

fn setupTokenSubmitHint(config_path: ?[]const u8) []const u8 {
    return if (config_path == null)
        "Enter: use token for this session  Esc: quit"
    else
        "Enter: save token and continue  Esc: quit";
}

test "app initializes with main menu screen" {
    const app = App.create(.{ .api = .{ .token = "token" } }, .{});

    try std.testing.expectEqual(Screen.main_menu, app.screen);
    try std.testing.expectEqualStrings("token", app.config.apiClientToken().?);
}

test "app starts on setup token screen without configured token" {
    const app = App.create(.{}, .{});

    try std.testing.expectEqual(Screen.setup_token, app.screen);
    try std.testing.expectEqual(@as(?[]const u8, null), app.config.apiClientToken());
}

test "menu indexes map to screens" {
    try std.testing.expectEqual(Screen.hot_games, screenForMenuIndex(0).?);
    try std.testing.expectEqual(Screen.search, screenForMenuIndex(1).?);
    try std.testing.expectEqual(Screen.collection, screenForMenuIndex(2).?);
    try std.testing.expectEqual(Screen.settings, screenForMenuIndex(3).?);
    try std.testing.expect(screenForMenuIndex(4) == null);
}

test "screen titles match status labels" {
    try std.testing.expectEqualStrings("setup token", screenTitle(.setup_token));
    try std.testing.expectEqualStrings("main menu", screenTitle(.main_menu));
    try std.testing.expectEqualStrings("hot games", screenTitle(.hot_games));
    try std.testing.expectEqualStrings("search", screenTitle(.search));
    try std.testing.expectEqualStrings("collection", screenTitle(.collection));
    try std.testing.expectEqualStrings("settings", screenTitle(.settings));
}

test "status right hint matches screen key handling" {
    try std.testing.expectEqualStrings("Esc: quit", statusRightHint(.setup_token));
    try std.testing.expectEqualStrings("m: menu  Esc/q: quit", statusRightHint(.main_menu));
    try std.testing.expectEqualStrings("m: menu  Esc/q: quit", statusRightHint(.hot_games));
}

test "setup token submit hint reflects save availability" {
    try std.testing.expectEqualStrings(
        "Enter: use token for this session  Esc: quit",
        setupTokenSubmitHint(null),
    );
    try std.testing.expectEqualStrings(
        "Enter: save token and continue  Esc: quit",
        setupTokenSubmitHint("/tmp/bgg-tui/config.toml"),
    );
}

test "setup token paste inserts printable token text" {
    var input = try ui.PasswordInput.init(std.testing.allocator, .{});
    defer input.deinit();

    try insertPastedToken(&input, " tok-123\n\tあ ");

    try std.testing.expectEqualStrings(" tok-123あ ", input.text());
}

test "setup token screen maps paste to paste message" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    app.setup_token_input = try ui.PasswordInput.init(std.testing.allocator, .{});
    defer app.deinitOwnedState();

    const msg = app.handleEvent(.{ .paste = "token" }).?;
    try std.testing.expect(msg == .setup_token_paste);
    try std.testing.expectEqualStrings("token", msg.setup_token_paste);
}

test "submit token stores owned token and enters main menu" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    app.setup_token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "  test-token  " });
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitToken(&tc.ctx);

    try std.testing.expectEqual(Screen.main_menu, app.screen);
    try std.testing.expectEqualStrings("test-token", app.config.apiClientToken().?);
    try std.testing.expectEqualStrings("", app.setup_token_input.?.text());
}

test "submit token saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-app-config/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.setup_token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "saved-token" });
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.submitToken(&tc.ctx);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("saved-token", loaded.config.apiClientToken().?);
}

test "hot game labels include rank and optional year" {
    const with_year = try formatHotGameLabel(std.testing.allocator, .{
        .id = 13,
        .rank = 1,
        .name = "CATAN",
        .year_published = 1995,
    });
    defer std.testing.allocator.free(with_year);

    const without_year = try formatHotGameLabel(std.testing.allocator, .{
        .id = 42,
        .rank = 12,
        .name = "Unknown Year",
    });
    defer std.testing.allocator.free(without_year);

    try std.testing.expectEqualStrings("# 1  CATAN (1995)", with_year);
    try std.testing.expectEqualStrings("#12  Unknown Year", without_year);
}

test "hot games state owns labels for loaded games" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "First") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Second"), .year_published = 2024 };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 2), state.list.items.len);
    try std.testing.expectEqualStrings("# 1  First", state.list.items[0]);
    try std.testing.expectEqualStrings("# 2  Second (2024)", state.list.items[1]);
}

test "surfaceRect creates a root-relative rectangle" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(80, 24);
    defer ts.deinit();

    try std.testing.expectEqual(chasen.Rect{
        .col = 0,
        .row = 0,
        .width = 80,
        .height = 24,
    }, surfaceRect(&ts.surface));
}
