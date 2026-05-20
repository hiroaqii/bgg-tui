const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_client = @import("bgg/client.zig");
const bgg_endpoint = @import("bgg/endpoint.zig");
const bgg_error = @import("bgg/error.zig");
const bgg_model = @import("bgg/model.zig");
const bgg_xml = @import("bgg/xml.zig");
const config_mod = @import("config.zig");
const format = @import("format.zig");
const list_filter = @import("list_filter.zig");
const list_view = @import("list_view.zig");

// Keep top-level screens centered until a screen needs its own full-page layout.
const main_menu_size = chasen.Size{ .width = 48, .height = 12 };
const setup_token_size = chasen.Size{ .width = 56, .height = 9 };
const placeholder_size = chasen.Size{ .width = 56, .height = 6 };
const list_screen_max_size = chasen.Size{ .width = 72, .height = 34 };
const detail_size = chasen.Size{ .width = 78, .height = 20 };

// List screens follow the Go version's vertical rhythm:
// row 0 title, row 1 blank, row 2 position, row 3 blank, row 4 list body.
const list_position_row: u16 = 2;
const list_body_row: u16 = 4;
const list_filter_row: u16 = 4;
const list_filtered_body_row: u16 = 6;

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
    search_results,
    game_detail,
    collection,
    settings,
};

pub const App = struct {
    config: config_mod.Config,
    config_path: ?[]const u8 = null,
    screen: Screen,
    allocator: ?std.mem.Allocator = null,
    setup_token_input: ?ui.PasswordInput = null,
    hot_filter_input: ?ui.TextInput = null,
    search_input: ?ui.TextInput = null,
    search_filter_input: ?ui.TextInput = null,
    collection_username_input: ?ui.TextInput = null,
    collection_filter_input: ?ui.TextInput = null,
    owned_token: ?[]u8 = null,
    hot_games: HotGamesState = .{},
    search: SearchState = .{},
    search_request_id: u64 = 0,
    collection: CollectionState = .{},
    collection_request_id: u64 = 0,
    game_detail: GameDetailState = .{},
    detail_request_id: u64 = 0,
    detail_back_screen: Screen = .main_menu,
    menu: ui.Menu = ui.Menu.init(.{ .items = &menu_items }),
    shell: ui.Panel = ui.Panel.init(.{}),

    pub const Msg = union(enum) {
        setup_token_input: ui.PasswordInput.Msg,
        setup_token_paste: []const u8,
        hot_filter_start,
        hot_filter_input: ui.TextInput.Msg,
        hot_filter_paste: []const u8,
        hot_filter_clear,
        search_input: ui.TextInput.Msg,
        search_paste: []const u8,
        search_filter_start,
        search_filter_input: ui.TextInput.Msg,
        search_filter_paste: []const u8,
        search_filter_clear,
        search_sort_toggle,
        search_results_loaded: SearchTaskResult,
        search_list: ui.List.Msg,
        collection_username_input: ui.TextInput.Msg,
        collection_username_paste: []const u8,
        collection_filter_start,
        collection_filter_input: ui.TextInput.Msg,
        collection_filter_paste: []const u8,
        collection_filter_clear,
        collection_items_loaded: CollectionTaskResult,
        collection_list: ui.List.Msg,
        game_detail_loaded: GameDetailTaskResult,
        menu: ui.Menu.Msg,
        hot_list: ui.List.Msg,
        hot_sort_toggle,
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
        self.hot_filter_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Filter hot games",
        });
        self.search_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Search board games",
        });
        self.search_filter_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Filter search results",
        });
        self.collection_username_input = try ui.TextInput.init(ctx.allocator(), .{
            .value = self.config.collection.default_username orelse "",
            .placeholder = "BGG username",
        });
        self.collection_filter_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Filter collection",
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
                    try insertPastedCodepoints(input, text);
                }
            },
            .hot_filter_start => try self.startHotFilter(),
            .hot_filter_input => |input_msg| {
                if (input_msg != .submit) {
                    if (self.hot_filter_input) |*input| try input.update(input_msg);
                    try self.applyHotFilter();
                }
            },
            .hot_filter_paste => |text| {
                if (self.hot_filter_input) |*input| {
                    try insertPastedCodepoints(input, text);
                    try self.applyHotFilter();
                }
            },
            .hot_filter_clear => try self.clearHotFilter(),
            .search_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.startSearch(ctx);
                } else if (self.search_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .search_paste => |text| {
                if (self.search_input) |*input| {
                    try insertPastedCodepoints(input, text);
                }
            },
            .search_filter_start => try self.startSearchFilter(),
            .search_filter_input => |input_msg| {
                if (input_msg != .submit) {
                    if (self.search_filter_input) |*input| try input.update(input_msg);
                    try self.applySearchFilter();
                }
            },
            .search_filter_paste => |text| {
                if (self.search_filter_input) |*input| {
                    try insertPastedCodepoints(input, text);
                    try self.applySearchFilter();
                }
            },
            .search_filter_clear => try self.clearSearchFilter(),
            .search_sort_toggle => try self.toggleSearchSort(),
            .search_results_loaded => |result| try self.finishSearch(result),
            .search_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.search.update(list_msg),
                .activate => |index| {
                    if (self.search.sourceIndex(index)) |source_index| try self.openSearchResult(source_index, ctx);
                },
            },
            .collection_username_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.startCollectionLoad(ctx);
                } else if (self.collection_username_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .collection_username_paste => |text| {
                if (self.collection_username_input) |*input| {
                    try insertPastedCodepoints(input, text);
                }
            },
            .collection_filter_start => try self.startCollectionFilter(),
            .collection_filter_input => |input_msg| {
                if (input_msg != .submit) {
                    if (self.collection_filter_input) |*input| try input.update(input_msg);
                    try self.applyCollectionFilter();
                }
            },
            .collection_filter_paste => |text| {
                if (self.collection_filter_input) |*input| {
                    try insertPastedCodepoints(input, text);
                    try self.applyCollectionFilter();
                }
            },
            .collection_filter_clear => try self.clearCollectionFilter(),
            .collection_items_loaded => |result| try self.finishCollectionLoad(result),
            .collection_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.collection.update(list_msg),
                .activate => |index| {
                    if (self.collection.sourceIndex(index)) |source_index| try self.openCollectionItem(source_index, ctx);
                },
            },
            .game_detail_loaded => |result| try self.finishGameDetail(result),
            .menu => |menu_msg| switch (menu_msg) {
                .move_prev, .move_next => self.menu.update(menu_msg),
                .activate => |index| {
                    if (screenForMenuIndex(index)) |screen| try self.showScreen(screen, ctx);
                },
            },
            .hot_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.hot_games.update(list_msg),
                .activate => |index| {
                    if (self.hot_games.sourceIndex(index)) |source_index| try self.openHotGame(source_index, ctx);
                },
            },
            .hot_sort_toggle => try self.toggleHotSort(),
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
            .right = self.footerHint(),
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

        if (self.screen == .search) {
            switch (event) {
                .key_press => |key| if (key.matches(chasen.Key.escape, .{})) return .{ .show_screen = .main_menu },
                .paste => |text| return .{ .search_paste = text },
                else => {},
            }
            if (self.search_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .search_input = msg };
            }
            return null;
        }

        if (self.screen == .search_results) {
            switch (event) {
                .key_press => |key| {
                    if (self.search.filter_active) {
                        if (key.matches(chasen.Key.escape, .{})) return .search_filter_clear;
                        if (key.codepoint == 'b') return .{ .show_screen = .search };
                        if (key.matches(chasen.Key.enter, .{})) {
                            if (self.search.handleEvent(event)) |msg| return .{ .search_list = msg };
                            return null;
                        }
                    } else if (key.codepoint == '/') {
                        return .search_filter_start;
                    } else {
                        if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .{ .show_screen = .search };
                        if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                        if (key.codepoint == 's') return .search_sort_toggle;
                        if (key.codepoint == 'q') return .quit;
                    }
                },
                .paste => |text| if (self.search.filter_active) return .{ .search_filter_paste = text },
                else => {},
            }
            if (self.search.filter_active) {
                if (self.search_filter_input) |*input| {
                    if (input.handleEvent(event)) |msg| return .{ .search_filter_input = msg };
                }
            }
            if (self.search.handleEvent(event)) |msg| return .{ .search_list = msg };
            return null;
        }

        if (self.screen == .game_detail) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .{ .show_screen = self.detail_back_screen };
                    if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.codepoint == 'q') return .quit;
                },
                else => {},
            }
            return null;
        }

        if (self.screen == .collection) {
            if (self.collection.filter_active) {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) return .collection_filter_clear;
                        if (key.matches(chasen.Key.enter, .{})) {
                            if (self.collection.handleEvent(event)) |msg| return .{ .collection_list = msg };
                            return null;
                        }
                    },
                    .paste => |text| return .{ .collection_filter_paste = text },
                    else => {},
                }
                if (self.collection_filter_input) |*input| {
                    if (input.handleEvent(event)) |msg| return .{ .collection_filter_input = msg };
                }
                if (self.collection.handleEvent(event)) |msg| return .{ .collection_list = msg };
                return null;
            }
            switch (event) {
                .key_press => |key| {
                    if (self.collection.load_state == .loaded) {
                        if (key.codepoint == '/') return .collection_filter_start;
                        if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'm') return .{ .show_screen = .main_menu };
                        if (key.codepoint == 'q') return .quit;
                    } else if (key.matches(chasen.Key.escape, .{})) {
                        return .{ .show_screen = .main_menu };
                    }
                },
                .paste => |text| if (self.collection.load_state != .loaded) return .{ .collection_username_paste = text },
                else => {},
            }
            if (self.collection.load_state == .loaded) {
                if (self.collection.handleEvent(event)) |msg| return .{ .collection_list = msg };
            } else if (self.collection_username_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .collection_username_input = msg };
            }
            return null;
        }

        if (self.screen == .hot_games) {
            if (self.hot_games.filter_active) {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) return .hot_filter_clear;
                        if (key.matches(chasen.Key.enter, .{})) {
                            if (self.hot_games.handleEvent(event)) |msg| return .{ .hot_list = msg };
                            return null;
                        }
                    },
                    .paste => |text| return .{ .hot_filter_paste = text },
                    else => {},
                }
                if (self.hot_filter_input) |*input| {
                    if (input.handleEvent(event)) |msg| return .{ .hot_filter_input = msg };
                }
                if (self.hot_games.handleEvent(event)) |msg| return .{ .hot_list = msg };
                return null;
            } else if (event == .key_press and event.key_press.codepoint == '/') {
                return .hot_filter_start;
            } else if (event == .key_press and event.key_press.codepoint == 's') {
                return .hot_sort_toggle;
            }
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
            .hot_games => try self.viewHotGames(sfc),
            .search => try self.viewSearch(sfc),
            .search_results => try self.viewSearchResults(sfc),
            .game_detail => try self.viewGameDetail(sfc),
            .collection => try self.viewCollection(sfc),
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

        _ = area.textAt(0, 10, self.footerHint(), .{ .dim = true });
    }

    fn viewPlaceholder(self: *const App, sfc: *chasen.Surface, title: []const u8, message: []const u8) void {
        var area = centeredSurface(sfc, placeholder_size);
        _ = area.textAt(0, 0, title, .{ .bold = true, .fg = .{ .index = 14 } });
        _ = area.textAt(0, 2, message, .{ .fg = .gray });
        _ = area.textAt(0, 4, self.footerHint(), .{ .dim = true });
    }

    fn viewHotGames(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = try area.printAt(0, 0, .{ .bold = true, .fg = .{ .index = 14 } }, "Hot Games ({s})", .{self.hot_games.sort_mode.label(.hot_games)});

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
                    self.drawEmptyState(&area, 2, "No hot games", "BGG did not return any hot games.");
                } else if (self.hot_games.filter_active and self.hot_games.filter.labels.len == 0) {
                    try self.drawHotFilterInput(&area);
                    self.drawEmptyState(&area, 6, "No matches", "No hot games match the filter.");
                } else {
                    const body_row = if (self.hot_games.filter_active) list_filtered_body_row else list_body_row;
                    if (self.hot_games.filter_active) try self.drawHotFilterInput(&area);
                    const list = self.hot_games.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                    self.drawSortMode(&area, self.hot_games.sort_mode.label(.hot_games));
                }
            },
        }

        _ = area.textAt(0, area.size().height -| 1, self.footerHint(), .{ .dim = true });
    }

    fn viewSearch(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = area.textAt(0, 0, "Search Games", .{ .bold = true, .fg = .{ .index = 14 } });

        if (self.search_input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 2, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        switch (self.search.load_state) {
            .idle => {
                self.drawGuidance(&area, 4, "Ready to search", "Enter at least 3 characters and press Enter.");
            },
            .loading => {
                _ = area.textAt(0, 4, "Search request is running...", .{ .fg = .gray });
            },
            .failed => |message| {
                _ = area.textAt(0, 4, "Could not search games.", .{ .fg = .{ .index = 9 } });
                _ = area.textAt(0, 6, message, .{ .fg = .gray });
            },
            .loaded => {
                self.drawGuidance(&area, 4, "Search complete", "Press Enter to run a new search.");
            },
        }

        _ = area.textAt(0, area.size().height -| 1, self.footerHint(), .{ .dim = true });
    }

    fn viewSearchResults(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = try area.printAt(0, 0, .{ .bold = true, .fg = .{ .index = 14 } }, "Search Results ({s})", .{self.search.sort_mode.label(.search_results)});

        switch (self.search.load_state) {
            .idle => {
                self.drawEmptyState(&area, 2, "No search yet", "Run a search to see matching board games.");
            },
            .loading => {
                area.hideCursor();
                _ = area.textAt(0, 2, "Searching BoardGameGeek...", .{ .fg = .gray });
            },
            .failed => |message| {
                _ = area.textAt(0, 2, "Could not search games.", .{ .fg = .{ .index = 9 } });
                _ = area.textAt(0, 4, message, .{ .fg = .gray });
            },
            .loaded => {
                if (self.search.list.items.len == 0) {
                    self.drawEmptyState(&area, 2, "No results", "No games matched the current query.");
                } else if (self.search.filter_active and self.search.filter.labels.len == 0) {
                    try self.drawSearchFilterInput(&area);
                    self.drawEmptyState(&area, 6, "No matches", "No search results match the filter.");
                } else {
                    const body_row = if (self.search.filter_active) list_filtered_body_row else list_body_row;
                    if (self.search.filter_active) try self.drawSearchFilterInput(&area);
                    const list = self.search.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                    self.drawSortMode(&area, self.search.sort_mode.label(.search_results));
                }
            },
        }

        _ = area.textAt(0, area.size().height -| 1, self.footerHint(), .{ .dim = true });
    }

    fn viewCollection(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = area.textAt(0, 0, "Collection", .{ .bold = true, .fg = .{ .index = 14 } });

        switch (self.collection.load_state) {
            .idle => {
                try self.drawCollectionUsernameInput(&area);
                self.drawGuidance(&area, 4, "Ready to load collection", "Enter a BGG username and press Enter.");
            },
            .loading => {
                area.hideCursor();
                _ = area.textAt(0, 2, "Loading BoardGameGeek collection...", .{ .fg = .gray });
            },
            .failed => |message| {
                try self.drawCollectionUsernameInput(&area);
                _ = area.textAt(0, 4, "Could not load collection.", .{ .fg = .{ .index = 9 } });
                _ = area.textAt(0, 6, message, .{ .fg = .gray });
            },
            .loaded => {
                if (self.collection.list.items.len == 0) {
                    self.drawEmptyState(&area, 2, "No collection items", "BGG did not return any games for this collection.");
                } else if (self.collection.filter_active and self.collection.filter.labels.len == 0) {
                    try self.drawCollectionFilterInput(&area);
                    self.drawEmptyState(&area, 6, "No matches", "No collection items match the filter.");
                } else {
                    const body_row = if (self.collection.filter_active) list_filtered_body_row else list_body_row;
                    if (self.collection.filter_active) try self.drawCollectionFilterInput(&area);
                    const list = self.collection.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                }
            },
        }

        _ = area.textAt(0, area.size().height -| 1, self.footerHint(), .{ .dim = true });
    }

    fn viewGameDetail(self: *const App, sfc: *chasen.Surface) !void {
        sfc.hideCursor();
        var area = centeredSurface(sfc, detail_size);
        _ = area.textAt(0, 0, "Game Detail", .{ .bold = true, .fg = .{ .index = 14 } });

        switch (self.game_detail.load_state) {
            .idle, .loading => {
                _ = area.textAt(0, 2, "Loading game detail...", .{ .fg = .gray });
            },
            .failed => |message| {
                _ = area.textAt(0, 2, "Could not load game detail.", .{ .fg = .{ .index = 9 } });
                _ = area.textAt(0, 4, message, .{ .fg = .gray });
            },
            .loaded => {
                if (self.game_detail.games.len == 0) {
                    self.drawEmptyState(&area, 2, "No detail", "BGG did not return game detail.");
                } else {
                    const game = self.game_detail.games[0];
                    if (game.year_published) |year| {
                        _ = try area.printAt(0, 2, .{ .bold = true }, "{s} ({d})", .{ game.name, year });
                    } else {
                        _ = area.textAt(0, 2, game.name, .{ .bold = true });
                    }

                    const frame = area.frameAllocator();
                    _ = area.textAt(0, 4, try formatText(frame, format.writePlayerSummary, .{game}), .{});
                    _ = area.textAt(0, 5, try formatText(frame, format.writeGameStats, .{game}), .{});
                    if (game.player_count_poll) |poll| {
                        _ = area.textAt(0, 6, try labeledFormattedText(frame, "Poll", format.writePlayerCountPollSummary, .{poll}), .{ .fg = .gray });
                    }

                    try drawListLine(&area, 7, "Designers", game.designers);
                    try drawListLine(&area, 8, "Artists", game.artists);
                    try drawListLine(&area, 9, "Publishers", game.publishers);
                    try drawListLine(&area, 10, "Categories", game.categories);
                    try drawListLine(&area, 11, "Mechanics", game.mechanics);

                    var desc_area = area.child(.{ .col = 0, .row = 13, .width = area.size().width, .height = area.size().height -| 16 });
                    drawDescriptionPreview(&desc_area, game.description);
                }
            },
        }

        _ = area.textAt(0, area.size().height -| 1, self.footerHint(), .{ .dim = true });
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
        if (self.hot_filter_input) |*input| {
            input.deinit();
            self.hot_filter_input = null;
        }
        if (self.search_input) |*input| {
            input.deinit();
            self.search_input = null;
        }
        if (self.search_filter_input) |*input| {
            input.deinit();
            self.search_filter_input = null;
        }
        if (self.collection_username_input) |*input| {
            input.deinit();
            self.collection_username_input = null;
        }
        if (self.collection_filter_input) |*input| {
            input.deinit();
            self.collection_filter_input = null;
        }
        if (self.owned_token) |token| {
            self.allocator.?.free(token);
            self.owned_token = null;
        }
        self.hot_games.deinit(self.allocator.?);
        self.search.deinit(self.allocator.?);
        self.collection.deinit(self.allocator.?);
        self.game_detail.deinit(self.allocator.?);
    }

    fn startHotFilter(self: *App) !void {
        if (self.hot_filter_input) |*input| try input.update(.clear);
        try self.hot_games.applyFilter(self.allocator.?, "");
    }

    fn applyHotFilter(self: *App) !void {
        const input = if (self.hot_filter_input) |*input| input else return;
        try self.hot_games.applyFilter(self.allocator.?, input.text());
    }

    fn clearHotFilter(self: *App) !void {
        if (self.hot_filter_input) |*input| try input.update(.clear);
        self.hot_games.clearFilter(self.allocator.?);
    }

    fn toggleHotSort(self: *App) !void {
        try self.hot_games.toggleSort(self.allocator.?);
    }

    fn startSearchFilter(self: *App) !void {
        if (self.search_filter_input) |*input| try input.update(.clear);
        try self.search.applyFilter(self.allocator.?, "");
    }

    fn applySearchFilter(self: *App) !void {
        const input = if (self.search_filter_input) |*input| input else return;
        try self.search.applyFilter(self.allocator.?, input.text());
    }

    fn clearSearchFilter(self: *App) !void {
        if (self.search_filter_input) |*input| try input.update(.clear);
        self.search.clearFilter(self.allocator.?);
    }

    fn toggleSearchSort(self: *App) !void {
        try self.search.toggleSort(self.allocator.?);
    }

    fn startCollectionFilter(self: *App) !void {
        if (self.collection_filter_input) |*input| try input.update(.clear);
        try self.collection.applyFilter(self.allocator.?, "");
    }

    fn applyCollectionFilter(self: *App) !void {
        const input = if (self.collection_filter_input) |*input| input else return;
        try self.collection.applyFilter(self.allocator.?, input.text());
    }

    fn clearCollectionFilter(self: *App) !void {
        if (self.collection_filter_input) |*input| try input.update(.clear);
        self.collection.clearFilter(self.allocator.?);
    }

    fn showScreen(self: *App, screen: Screen, ctx: *chasen.Ctx(Msg)) !void {
        const previous_screen = self.screen;
        self.screen = screen;
        if (screen == .hot_games) {
            try self.startHotGamesLoad(ctx);
        }
        if (screen == .search and previous_screen != .search_results) {
            try self.resetSearchScreen();
        }
    }

    fn resetSearchScreen(self: *App) !void {
        if (self.search_input) |*input| {
            try input.update(.clear);
        }
        self.search_request_id +%= 1;
        self.search.deinit(self.allocator.?);
    }

    fn openHotGame(self: *App, index: usize, ctx: *chasen.Ctx(Msg)) !void {
        if (index >= self.hot_games.games.len) return;
        try self.startGameDetail(ctx, self.hot_games.games[index].id, .hot_games);
    }

    fn openSearchResult(self: *App, index: usize, ctx: *chasen.Ctx(Msg)) !void {
        if (index >= self.search.results.len) return;
        try self.startGameDetail(ctx, self.search.results[index].id, .search_results);
    }

    fn openCollectionItem(self: *App, index: usize, ctx: *chasen.Ctx(Msg)) !void {
        if (index >= self.collection.items.len) return;
        try self.startGameDetail(ctx, self.collection.items[index].id, .collection);
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

    fn startSearch(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.search_input) |*input| input else return;
        const query = std.mem.trim(u8, input.text(), " \t\r\n");
        // Every submit represents the current search intent. Bump the request
        // id before validation so older in-flight tasks cannot replace a new
        // validation or auth failure state.
        self.search_request_id +%= 1;
        const request_id = self.search_request_id;

        if (query.len < 3) {
            self.search.setFailed(self.allocator.?, "Search query must be at least 3 characters");
            return;
        }

        const token = self.config.apiClientToken() orelse {
            self.search.setFailed(self.allocator.?, "BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(SearchTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .query = try ctx.allocator().dupe(u8, query),
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.token);
        errdefer ctx.allocator().free(task.query);

        self.screen = .search_results;
        self.search.setLoading(self.allocator.?);
        ctx.spawnWith(task, SearchTask.run) catch |err| {
            self.search.setFailed(self.allocator.?, "Could not start search task");
            return err;
        };
    }

    fn finishSearch(self: *App, task_result: SearchTaskResult) !void {
        if (task_result.request_id != self.search_request_id) {
            switch (task_result.result) {
                .ok => |results| bgg_xml.freeSearchResults(self.allocator.?, results),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |results| {
                try self.search.setLoaded(self.allocator.?, results);
            },
            .failed => |message| self.search.setFailed(self.allocator.?, message),
        }
    }

    fn startCollectionLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.collection_username_input) |*input| input else return;
        const username = std.mem.trim(u8, input.text(), " \t\r\n");
        self.collection_request_id +%= 1;
        const request_id = self.collection_request_id;

        if (username.len == 0) {
            self.collection.setFailed(self.allocator.?, "BGG username is required");
            return;
        }

        const token = self.config.apiClientToken() orelse {
            self.collection.setFailed(self.allocator.?, "BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(CollectionTask);
        errdefer ctx.allocator().destroy(task);

        const task_token = try ctx.allocator().dupe(u8, token);
        errdefer ctx.allocator().free(task_token);

        const task_username = try ctx.allocator().dupe(u8, username);
        errdefer ctx.allocator().free(task_username);

        task.* = .{
            .token = task_token,
            .username = task_username,
            .status_filter = self.config.collection.status_filter,
            .request_id = request_id,
        };

        self.collection.setLoading(self.allocator.?);
        ctx.spawnWith(task, CollectionTask.run) catch |err| {
            self.collection.setFailed(self.allocator.?, "Could not start collection loading task");
            return err;
        };
    }

    fn finishCollectionLoad(self: *App, task_result: CollectionTaskResult) !void {
        if (task_result.request_id != self.collection_request_id) {
            switch (task_result.result) {
                .ok => |items| bgg_xml.freeCollectionItems(self.allocator.?, items),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |items| try self.collection.setLoaded(self.allocator.?, items),
            .failed => |message| self.collection.setFailed(self.allocator.?, message),
        }
    }

    fn startGameDetail(self: *App, ctx: *chasen.Ctx(Msg), game_id: u32, back_screen: Screen) !void {
        self.detail_request_id +%= 1;
        const request_id = self.detail_request_id;
        self.detail_back_screen = back_screen;
        self.screen = .game_detail;
        self.game_detail.deinit(self.allocator.?);

        const token = self.config.apiClientToken() orelse {
            self.game_detail.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(GameDetailTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .game_id = game_id,
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.token);

        self.game_detail.setLoading();
        ctx.spawnWith(task, GameDetailTask.run) catch |err| {
            self.game_detail.setFailed("Could not start game detail task");
            return err;
        };
    }

    fn finishGameDetail(self: *App, task_result: GameDetailTaskResult) !void {
        if (task_result.request_id != self.detail_request_id) {
            switch (task_result.result) {
                .ok => |games| bgg_xml.freeGames(self.allocator.?, games),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |games| try self.game_detail.setLoaded(self.allocator.?, games),
            .failed => |message| self.game_detail.setFailed(message),
        }
    }

    fn drawListPosition(self: *const App, surface: *chasen.Surface, list: *const ui.List) !void {
        _ = self;
        const item_count = list.items.len;
        if (item_count == 0 or surface.size().height < 2) return;

        const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
        _ = surface.textAt(0, list_position_row, text, .{ .dim = true });
    }

    fn drawSortMode(self: *const App, surface: *chasen.Surface, label: []const u8) void {
        _ = self;
        if (surface.size().width <= 12 or surface.size().height <= list_position_row) return;
        _ = surface.textAt(10, list_position_row, label, .{ .dim = true });
    }

    fn drawEmptyState(self: *const App, surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8) void {
        surface.hideCursor();
        self.drawGuidance(surface, row, title, message);
    }

    fn drawGuidance(self: *const App, surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8) void {
        _ = self;
        _ = surface.textAt(0, row, title, .{ .bold = true, .fg = .gray });
        _ = surface.textAt(0, row + 1, message, .{ .fg = .gray });
    }

    fn drawHotFilterInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.textAt(0, list_filter_row, "Filter:", .{ .dim = true });
        if (self.hot_filter_input) |*input| {
            var input_area = surface.child(.{
                .col = 8,
                .row = list_filter_row,
                .width = surface.size().width -| 8,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    fn drawSearchFilterInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.textAt(0, list_filter_row, "Filter:", .{ .dim = true });
        if (self.search_filter_input) |*input| {
            var input_area = surface.child(.{
                .col = 8,
                .row = list_filter_row,
                .width = surface.size().width -| 8,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    fn drawCollectionUsernameInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.textAt(0, 2, "User:", .{ .dim = true });
        if (self.collection_username_input) |*input| {
            var input_area = surface.child(.{
                .col = 6,
                .row = 2,
                .width = surface.size().width -| 6,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    fn drawCollectionFilterInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.textAt(0, list_filter_row, "Filter:", .{ .dim = true });
        if (self.collection_filter_input) |*input| {
            var input_area = surface.child(.{
                .col = 8,
                .row = list_filter_row,
                .width = surface.size().width -| 8,
                .height = 1,
            });
            input.view(&input_area, .{});
        }
    }

    fn listDensity(self: *const App) list_view.Density {
        return list_view.Density.fromConfig(self.config.interface.list_density);
    }

    fn footerHint(self: *const App) []const u8 {
        return switch (self.screen) {
            .setup_token => setupTokenSubmitHint(self.config_path),
            .main_menu => "Up/Down: move  Enter: open  h, /, c, s: shortcuts  Esc/q: quit",
            .hot_games => if (self.hot_games.filter_active)
                "Type: filter  Up/Down: move  Enter: detail  Esc: clear"
            else
                "Up/Down: move  Enter: detail  /: filter  s: sort  m: menu  Esc/q: quit",
            .search => "Enter: search  Esc: menu",
            .search_results => if (self.search.filter_active)
                "Type: filter  Up/Down: move  Enter: detail  Esc: clear  b: search"
            else
                "Up/Down: move  Enter: detail  /: filter  s: sort  b/Esc: search  m: menu  q: quit",
            .game_detail => "b/Esc: back  m: menu  q: quit",
            .collection => switch (self.collection.load_state) {
                .idle, .failed => "Enter: load  Esc: menu",
                .loading => "Esc: menu",
                .loaded => if (self.collection.filter_active)
                    "Type: filter  Up/Down: move  Enter: detail  Esc: clear"
                else
                    "Up/Down: move  Enter: detail  /: filter  Esc/m: menu  q: quit",
            },
            .settings => "m: menu  Esc/q: quit",
        };
    }
};

const HotGamesState = struct {
    load_state: LoadState = .idle,
    games: []bgg_model.HotGame = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    sort_mode: ListSortMode = .source,
    sorted_source_indexes: []usize = &.{},
    sorted_labels: []const []const u8 = &.{},
    sorted_list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,

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
        if (self.filter_active) {
            self.filter.update(msg);
        } else if (self.sort_mode != .source) {
            self.sorted_list.update(msg);
        } else {
            self.list.update(msg);
        }
    }

    fn handleEvent(self: *const HotGamesState, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        if (self.filter_active) return self.filter.handleEvent(event);
        if (self.sort_mode != .source) return self.sorted_list.handleEvent(event);
        return self.list.handleEvent(event);
    }

    fn activeList(self: *const HotGamesState) *const ui.List {
        if (self.filter_active) return &self.filter.list;
        if (self.sort_mode != .source) return &self.sorted_list;
        return &self.list;
    }

    fn sourceIndex(self: *const HotGamesState, visible_index: usize) ?usize {
        if (self.filter_active) return self.filter.sourceIndex(visible_index);
        if (self.sort_mode != .source) {
            if (visible_index >= self.sorted_source_indexes.len) return null;
            return self.sorted_source_indexes[visible_index];
        }
        if (visible_index >= self.games.len) return null;
        return visible_index;
    }

    fn applyFilter(self: *HotGamesState, allocator: std.mem.Allocator, query: []const u8) !void {
        if (self.sort_mode == .source) {
            try self.filter.apply(allocator, self.labels, query);
        } else {
            try self.filter.applyWithSourceIndexes(allocator, self.sorted_labels, self.sorted_source_indexes, query);
        }
        self.filter_active = true;
    }

    fn clearFilter(self: *HotGamesState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    fn toggleSort(self: *HotGamesState, allocator: std.mem.Allocator) !void {
        if (self.load_state != .loaded) return;

        const next_mode = self.sort_mode.next();
        if (next_mode != .source) {
            try self.rebuildSortedList(allocator, next_mode);
        } else {
            self.freeSortedList(allocator);
        }

        self.sort_mode = next_mode;
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    fn rebuildSortedList(self: *HotGamesState, allocator: std.mem.Allocator, mode: ListSortMode) !void {
        const indexes = try allocator.alloc(usize, self.games.len);
        errdefer allocator.free(indexes);
        for (indexes, 0..) |*index, value| index.* = value;

        switch (mode) {
            .source => {},
            .name_asc => std.mem.sort(usize, indexes, self.games, hotGameNameLessThan),
        }

        const labels = try allocator.alloc([]const u8, indexes.len);
        errdefer allocator.free(labels);
        for (indexes, 0..) |source_index, display_index| {
            labels[display_index] = self.labels[source_index];
        }

        self.freeSortedList(allocator);
        self.sorted_source_indexes = indexes;
        self.sorted_labels = labels;
        self.sorted_list = ui.List.init(.{ .items = self.sorted_labels });
    }

    fn freeSortedList(self: *HotGamesState, allocator: std.mem.Allocator) void {
        allocator.free(self.sorted_source_indexes);
        allocator.free(self.sorted_labels);
        self.sorted_source_indexes = &.{};
        self.sorted_labels = &.{};
        self.sorted_list = ui.List.init(.{});
    }

    fn deinit(self: *HotGamesState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.freeSortedList(allocator);
        freeHotGameLabels(allocator, self.labels);
        bgg_xml.freeHotGames(allocator, self.games);
        self.labels = &.{};
        self.games = &.{};
        self.list = ui.List.init(.{});
        self.sort_mode = .source;
        self.filter_active = false;
        self.load_state = .idle;
    }
};

const HotGamesResult = union(enum) {
    ok: []bgg_model.HotGame,
    failed: []const u8,
};

const SearchState = struct {
    load_state: LoadState = .idle,
    results: []bgg_model.GameSearchResult = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    sort_mode: ListSortMode = .source,
    sorted_source_indexes: []usize = &.{},
    sorted_labels: []const []const u8 = &.{},
    sorted_list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,

    const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    fn setLoading(self: *SearchState, allocator: std.mem.Allocator) void {
        self.clearResults(allocator);
        self.load_state = .loading;
    }

    fn setFailed(self: *SearchState, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearResults(allocator);
        self.load_state = .{ .failed = message };
    }

    fn setLoaded(self: *SearchState, allocator: std.mem.Allocator, results: []bgg_model.GameSearchResult) !void {
        self.clearResults(allocator);
        self.results = results;
        self.labels = try buildSearchResultLabels(allocator, results);
        self.list = ui.List.init(.{ .items = self.labels });
        self.load_state = .loaded;
    }

    fn update(self: *SearchState, msg: ui.List.Msg) void {
        if (self.filter_active) {
            self.filter.update(msg);
        } else if (self.sort_mode != .source) {
            self.sorted_list.update(msg);
        } else {
            self.list.update(msg);
        }
    }

    fn handleEvent(self: *const SearchState, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        if (self.filter_active) return self.filter.handleEvent(event);
        if (self.sort_mode != .source) return self.sorted_list.handleEvent(event);
        return self.list.handleEvent(event);
    }

    fn activeList(self: *const SearchState) *const ui.List {
        if (self.filter_active) return &self.filter.list;
        if (self.sort_mode != .source) return &self.sorted_list;
        return &self.list;
    }

    fn sourceIndex(self: *const SearchState, visible_index: usize) ?usize {
        if (self.filter_active) return self.filter.sourceIndex(visible_index);
        if (self.sort_mode != .source) {
            if (visible_index >= self.sorted_source_indexes.len) return null;
            return self.sorted_source_indexes[visible_index];
        }
        if (visible_index >= self.results.len) return null;
        return visible_index;
    }

    fn applyFilter(self: *SearchState, allocator: std.mem.Allocator, query: []const u8) !void {
        if (self.sort_mode == .source) {
            try self.filter.apply(allocator, self.labels, query);
        } else {
            try self.filter.applyWithSourceIndexes(allocator, self.sorted_labels, self.sorted_source_indexes, query);
        }
        self.filter_active = true;
    }

    fn clearFilter(self: *SearchState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    fn toggleSort(self: *SearchState, allocator: std.mem.Allocator) !void {
        if (self.load_state != .loaded) return;

        const next_mode = self.sort_mode.next();
        if (next_mode != .source) {
            try self.rebuildSortedList(allocator, next_mode);
        } else {
            self.freeSortedList(allocator);
        }

        self.sort_mode = next_mode;
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    fn rebuildSortedList(self: *SearchState, allocator: std.mem.Allocator, mode: ListSortMode) !void {
        const indexes = try allocator.alloc(usize, self.results.len);
        errdefer allocator.free(indexes);
        for (indexes, 0..) |*index, value| index.* = value;

        switch (mode) {
            .source => {},
            .name_asc => std.mem.sort(usize, indexes, self.results, searchResultNameLessThan),
        }

        const labels = try allocator.alloc([]const u8, indexes.len);
        errdefer allocator.free(labels);
        for (indexes, 0..) |source_index, display_index| {
            labels[display_index] = self.labels[source_index];
        }

        self.freeSortedList(allocator);
        self.sorted_source_indexes = indexes;
        self.sorted_labels = labels;
        self.sorted_list = ui.List.init(.{ .items = self.sorted_labels });
    }

    fn freeSortedList(self: *SearchState, allocator: std.mem.Allocator) void {
        allocator.free(self.sorted_source_indexes);
        allocator.free(self.sorted_labels);
        self.sorted_source_indexes = &.{};
        self.sorted_labels = &.{};
        self.sorted_list = ui.List.init(.{});
    }

    fn deinit(self: *SearchState, allocator: std.mem.Allocator) void {
        self.clearResults(allocator);
        self.load_state = .idle;
    }

    fn clearResults(self: *SearchState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.freeSortedList(allocator);
        freeSearchResultLabels(allocator, self.labels);
        bgg_xml.freeSearchResults(allocator, self.results);
        self.labels = &.{};
        self.results = &.{};
        self.list = ui.List.init(.{});
        self.sort_mode = .source;
        self.filter_active = false;
    }
};

const SearchResult = union(enum) {
    ok: []bgg_model.GameSearchResult,
    failed: []const u8,
};

const SearchTaskResult = struct {
    request_id: u64,
    result: SearchResult,
};

const CollectionState = struct {
    load_state: LoadState = .idle,
    items: []bgg_model.CollectionItem = &.{},
    labels: []const []const u8 = &.{},
    list: ui.List = ui.List.init(.{}),
    filter: list_filter.FilterState = .{},
    filter_active: bool = false,

    const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    fn setLoading(self: *CollectionState, allocator: std.mem.Allocator) void {
        self.clearItems(allocator);
        self.load_state = .loading;
    }

    fn setFailed(self: *CollectionState, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearItems(allocator);
        self.load_state = .{ .failed = message };
    }

    fn setLoaded(self: *CollectionState, allocator: std.mem.Allocator, items: []bgg_model.CollectionItem) !void {
        self.clearItems(allocator);
        self.items = items;
        self.labels = try buildCollectionItemLabels(allocator, items);
        self.list = ui.List.init(.{ .items = self.labels });
        self.load_state = .loaded;
    }

    fn update(self: *CollectionState, msg: ui.List.Msg) void {
        if (self.filter_active) {
            self.filter.update(msg);
        } else {
            self.list.update(msg);
        }
    }

    fn handleEvent(self: *const CollectionState, event: chasen.Event) ?ui.List.Msg {
        if (self.load_state != .loaded) return null;
        if (self.filter_active) return self.filter.handleEvent(event);
        if (self.list.items.len == 0) return null;
        return self.list.handleEvent(event);
    }

    fn activeList(self: *const CollectionState) *const ui.List {
        if (self.filter_active) return &self.filter.list;
        return &self.list;
    }

    fn sourceIndex(self: *const CollectionState, visible_index: usize) ?usize {
        if (self.filter_active) return self.filter.sourceIndex(visible_index);
        if (visible_index >= self.items.len) return null;
        return visible_index;
    }

    fn applyFilter(self: *CollectionState, allocator: std.mem.Allocator, query: []const u8) !void {
        try self.filter.apply(allocator, self.labels, query);
        self.filter_active = true;
    }

    fn clearFilter(self: *CollectionState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        self.filter_active = false;
    }

    fn deinit(self: *CollectionState, allocator: std.mem.Allocator) void {
        self.clearItems(allocator);
        self.load_state = .idle;
    }

    fn clearItems(self: *CollectionState, allocator: std.mem.Allocator) void {
        self.filter.deinit(allocator);
        freeCollectionItemLabels(allocator, self.labels);
        bgg_xml.freeCollectionItems(allocator, self.items);
        self.labels = &.{};
        self.items = &.{};
        self.list = ui.List.init(.{});
        self.filter_active = false;
    }
};

const CollectionResult = union(enum) {
    ok: []bgg_model.CollectionItem,
    failed: []const u8,
};

const CollectionTaskResult = struct {
    request_id: u64,
    result: CollectionResult,
};

const GameDetailState = struct {
    load_state: LoadState = .idle,
    games: []bgg_model.Game = &.{},

    const LoadState = union(enum) {
        idle,
        loading,
        loaded,
        failed: []const u8,
    };

    fn setLoading(self: *GameDetailState) void {
        self.load_state = .loading;
    }

    fn setFailed(self: *GameDetailState, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    fn setLoaded(self: *GameDetailState, allocator: std.mem.Allocator, games: []bgg_model.Game) !void {
        self.deinit(allocator);
        self.games = games;
        self.load_state = .loaded;
    }

    fn deinit(self: *GameDetailState, allocator: std.mem.Allocator) void {
        bgg_xml.freeGames(allocator, self.games);
        self.games = &.{};
        self.load_state = .idle;
    }
};

const GameDetailResult = union(enum) {
    ok: []bgg_model.Game,
    failed: []const u8,
};

const GameDetailTaskResult = struct {
    request_id: u64,
    result: GameDetailResult,
};

const ListSortMode = enum {
    source,
    name_asc,

    fn next(self: ListSortMode) ListSortMode {
        return switch (self) {
            .source => .name_asc,
            .name_asc => .source,
        };
    }

    fn label(self: ListSortMode, screen: Screen) []const u8 {
        return switch (self) {
            .source => switch (screen) {
                .hot_games => "rank",
                .search_results => "relevance",
                else => "default",
            },
            .name_asc => "name",
        };
    }
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

const SearchTask = struct {
    token: []const u8,
    query: []const u8,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *SearchTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.free(task.query);
            allocator.destroy(task);
        }

        return .{ .search_results_loaded = .{
            .request_id = task.request_id,
            .result = loadSearchResults(allocator, io, task.token, task.query) catch |err| .{ .failed = @errorName(err) },
        } };
    }
};

const CollectionTask = struct {
    token: []const u8,
    username: []const u8,
    status_filter: config_mod.CollectionStatus,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *CollectionTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.free(task.username);
            allocator.destroy(task);
        }

        return .{ .collection_items_loaded = .{
            .request_id = task.request_id,
            .result = loadCollectionItems(allocator, io, task.token, task.username, task.status_filter) catch |err| .{ .failed = @errorName(err) },
        } };
    }
};

const GameDetailTask = struct {
    token: []const u8,
    game_id: u32,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *GameDetailTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.destroy(task);
        }

        return .{ .game_detail_loaded = .{
            .request_id = task.request_id,
            .result = loadGameDetail(allocator, io, task.token, task.game_id) catch |err| .{ .failed = @errorName(err) },
        } };
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

fn loadSearchResults(allocator: std.mem.Allocator, io: std.Io, token: []const u8, query: []const u8) !SearchResult {
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

fn loadCollectionItems(
    allocator: std.mem.Allocator,
    io: std.Io,
    token: []const u8,
    username: []const u8,
    status_filter: config_mod.CollectionStatus,
) !CollectionResult {
    var client = bgg_client.Client.init(allocator, io, .{ .token = token });
    defer client.deinit();

    const path = try bgg_endpoint.collection(allocator, username, collectionOptionsForStatus(status_filter));
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

fn loadGameDetail(allocator: std.mem.Allocator, io: std.Io, token: []const u8, game_id: u32) !GameDetailResult {
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

fn drawDescriptionPreview(surface: *chasen.Surface, description: []const u8) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    _ = surface.textAt(0, 0, "Description", .{ .bold = true });
    if (description.len == 0) {
        _ = surface.textAt(0, 2, "-", .{ .fg = .gray });
        return;
    }

    var row: u16 = 2;
    var line_start: usize = 0;
    var index: usize = 0;
    while (index <= description.len and row < size.height) : (index += 1) {
        if (index == description.len or description[index] == '\n') {
            const line = std.mem.trim(u8, description[line_start..index], " \t\r");
            if (line.len > 0) {
                _ = surface.textAt(0, row, line, .{});
                row += 1;
            }
            line_start = index + 1;
        }
    }
}

fn drawListLine(surface: *chasen.Surface, row: u16, label: []const u8, values: []const []const u8) !void {
    if (row >= surface.size().height) return;
    const text = try listLineText(surface.frameAllocator(), label, values);
    _ = surface.textAt(0, row, text, .{ .fg = .gray });
}

fn listLineText(allocator: std.mem.Allocator, label: []const u8, values: []const []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.print("{s}: ", .{label});
    if (values.len == 0) {
        try out.writer.writeByte('-');
    } else {
        for (values, 0..) |value, index| {
            if (index > 0) try out.writer.writeAll(", ");
            try out.writer.writeAll(value);
        }
    }

    return try out.toOwnedSlice();
}

fn formatText(allocator: std.mem.Allocator, write_fn: anytype, args: anytype) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try @call(.auto, write_fn, .{&out.writer} ++ args);
    return try out.toOwnedSlice();
}

fn labeledFormattedText(allocator: std.mem.Allocator, label: []const u8, write_fn: anytype, args: anytype) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.print("{s}: ", .{label});
    try @call(.auto, write_fn, .{&out.writer} ++ args);
    return try out.toOwnedSlice();
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

fn buildSearchResultLabels(allocator: std.mem.Allocator, results: []const bgg_model.GameSearchResult) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, results.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    for (results, 0..) |result, index| {
        labels[index] = try formatSearchResultLabel(allocator, result);
        initialized_count = index + 1;
    }

    return labels;
}

fn formatSearchResultLabel(allocator: std.mem.Allocator, result: bgg_model.GameSearchResult) ![]u8 {
    if (result.year_published) |year| {
        return try std.fmt.allocPrint(allocator, "{s} ({d})", .{ result.name, year });
    }
    return try allocator.dupe(u8, result.name);
}

fn freeSearchResultLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
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

fn buildCollectionItemLabels(allocator: std.mem.Allocator, items: []const bgg_model.CollectionItem) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, items.len);
    var initialized_count: usize = 0;
    errdefer {
        for (labels[0..initialized_count]) |label| allocator.free(label);
        allocator.free(labels);
    }

    for (items, 0..) |item, index| {
        labels[index] = try formatCollectionItemLabel(allocator, item);
        initialized_count = index + 1;
    }

    return labels;
}

fn formatCollectionItemLabel(allocator: std.mem.Allocator, item: bgg_model.CollectionItem) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll(item.name);
    if (item.year_published) |year| try out.writer.print(" ({d})", .{year});

    // Keep the label single-line for the current list component while still
    // surfacing the core collection metadata users need for scanning.
    try out.writer.writeAll("  ");
    try writeCollectionRating(&out.writer, "user", item.rating);
    try out.writer.writeAll("  ");
    try writeCollectionRating(&out.writer, "BGG", item.bgg_rating);
    if (item.rank > 0) try out.writer.print("  rank #{d}", .{item.rank});
    if (item.num_plays > 0) try out.writer.print("  plays {d}", .{item.num_plays});

    return try out.toOwnedSlice();
}

fn freeCollectionItemLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

fn writeCollectionRating(writer: *std.Io.Writer, label: []const u8, rating: f64) !void {
    try writer.print("{s} ", .{label});
    if (rating <= 0) {
        try writer.writeByte('-');
    } else {
        try writer.print("{d:.1}", .{rating});
    }
}

fn collectionOptionsForStatus(status: config_mod.CollectionStatus) bgg_endpoint.CollectionOptions {
    return switch (status) {
        .own => .{ .own = true },
        .prev_owned => .{ .prev_owned = true },
        .for_trade => .{ .for_trade = true },
        .want => .{ .want = true },
        .want_to_play => .{ .want_to_play = true },
        .want_to_buy => .{ .want_to_buy = true },
        .wishlist => .{ .wishlist = true },
        .preordered => .{ .preordered = true },
    };
}

fn hotGameNameLessThan(games: []const bgg_model.HotGame, lhs: usize, rhs: usize) bool {
    const order = compareAsciiIgnoreCase(games[lhs].name, games[rhs].name);
    if (order == .eq) return lhs < rhs;
    return order == .lt;
}

fn searchResultNameLessThan(results: []const bgg_model.GameSearchResult, lhs: usize, rhs: usize) bool {
    const order = compareAsciiIgnoreCase(results[lhs].name, results[rhs].name);
    if (order == .eq) return lhs < rhs;
    return order == .lt;
}

fn compareAsciiIgnoreCase(lhs: []const u8, rhs: []const u8) std.math.Order {
    const len = @min(lhs.len, rhs.len);
    for (lhs[0..len], rhs[0..len]) |lhs_byte, rhs_byte| {
        const left = std.ascii.toLower(lhs_byte);
        const right = std.ascii.toLower(rhs_byte);
        if (left < right) return .lt;
        if (left > right) return .gt;
    }
    return std.math.order(lhs.len, rhs.len);
}

// App screens receive a local surface. `ui.layout.center` handles clamping when
// the terminal is smaller than the requested block.
fn centeredSurface(surface: *chasen.Surface, size: chasen.Size) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), size));
}

fn constrainedListSurface(surface: *chasen.Surface) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), list_screen_max_size));
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
        .search_results => "search results",
        .game_detail => "game detail",
        .collection => "collection",
        .settings => "settings",
    };
}

fn insertPastedCodepoints(input: anytype, text: []const u8) !void {
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
    try std.testing.expectEqualStrings("search results", screenTitle(.search_results));
    try std.testing.expectEqualStrings("game detail", screenTitle(.game_detail));
    try std.testing.expectEqualStrings("collection", screenTitle(.collection));
    try std.testing.expectEqualStrings("settings", screenTitle(.settings));
}

test "footer hint matches screen key handling" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});

    app.screen = .main_menu;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: open  h, /, c, s: shortcuts  Esc/q: quit", app.footerHint());

    app.screen = .hot_games;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: detail  /: filter  s: sort  m: menu  Esc/q: quit", app.footerHint());
    app.hot_games.filter_active = true;
    try std.testing.expectEqualStrings("Type: filter  Up/Down: move  Enter: detail  Esc: clear", app.footerHint());
    app.hot_games.filter_active = false;

    app.screen = .search;
    try std.testing.expectEqualStrings("Enter: search  Esc: menu", app.footerHint());

    app.screen = .search_results;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: detail  /: filter  s: sort  b/Esc: search  m: menu  q: quit", app.footerHint());
    app.search.filter_active = true;
    try std.testing.expectEqualStrings("Type: filter  Up/Down: move  Enter: detail  Esc: clear  b: search", app.footerHint());
    app.search.filter_active = false;

    app.screen = .game_detail;
    try std.testing.expectEqualStrings("b/Esc: back  m: menu  q: quit", app.footerHint());

    app.screen = .collection;
    try std.testing.expectEqualStrings("Enter: load  Esc: menu", app.footerHint());
    app.collection.load_state = .loading;
    try std.testing.expectEqualStrings("Esc: menu", app.footerHint());
    app.collection.load_state = .loaded;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: detail  /: filter  Esc/m: menu  q: quit", app.footerHint());
    app.collection.filter_active = true;
    try std.testing.expectEqualStrings("Type: filter  Up/Down: move  Enter: detail  Esc: clear", app.footerHint());
    app.collection.filter_active = false;
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

    try insertPastedCodepoints(&input, " tok-123\n\tあ ");

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

test "search paste inserts printable query text" {
    var input = try ui.TextInput.init(std.testing.allocator, .{});
    defer input.deinit();

    try insertPastedCodepoints(&input, "Catan\n\tDuel");

    try std.testing.expectEqualStrings("CatanDuel", input.text());
}

test "collection username input starts from config default" {
    var app = App.create(.{
        .api = .{ .token = "token" },
        .collection = .{ .default_username = "hiro" },
    }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);

    try std.testing.expectEqualStrings("hiro", app.collection_username_input.?.text());
}

test "detail list line text joins metadata values" {
    const values = [_][]const u8{ "Klaus Teuber", "Tanja Donner" };
    const text = try listLineText(std.testing.allocator, "Designers", &values);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Designers: Klaus Teuber, Tanja Donner", text);
}

test "detail list line text uses dash for missing metadata" {
    const text = try listLineText(std.testing.allocator, "Mechanics", &.{});
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Mechanics: -", text);
}

test "search query shorter than three characters fails before spawning task" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.search_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "go" });
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startSearch(&tc.ctx);

    try std.testing.expect(app.search.load_state == .failed);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "collection empty username fails before spawning task" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.collection_username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "  " });
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startCollectionLoad(&tc.ctx);

    try std.testing.expect(app.collection.load_state == .failed);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "collection status config maps to endpoint options" {
    try std.testing.expect(collectionOptionsForStatus(.own).own);
    try std.testing.expect(collectionOptionsForStatus(.prev_owned).prev_owned);
    try std.testing.expect(collectionOptionsForStatus(.for_trade).for_trade);
    try std.testing.expect(collectionOptionsForStatus(.want).want);
    try std.testing.expect(collectionOptionsForStatus(.want_to_play).want_to_play);
    try std.testing.expect(collectionOptionsForStatus(.want_to_buy).want_to_buy);
    try std.testing.expect(collectionOptionsForStatus(.wishlist).wishlist);
    try std.testing.expect(collectionOptionsForStatus(.preordered).preordered);
}

test "search screen escape returns to main menu" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .search;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expectEqual(App.Msg{ .show_screen = .main_menu }, msg);
}

test "showing search from non-detail screen resets previous query and results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    app.search_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    try app.search.setLoaded(std.testing.allocator, results);
    app.search_request_id = 7;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.showScreen(.search, &tc.ctx);

    try std.testing.expectEqual(Screen.search, app.screen);
    try std.testing.expectEqualStrings("", app.search_input.?.text());
    try std.testing.expect(app.search.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.search.results.len);
    try std.testing.expectEqual(@as(u64, 8), app.search_request_id);
}

test "showing search from search results preserves previous query and results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .search_results;
    app.search_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    try app.search.setLoaded(std.testing.allocator, results);
    app.search_request_id = 7;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.showScreen(.search, &tc.ctx);

    try std.testing.expectEqual(Screen.search, app.screen);
    try std.testing.expectEqualStrings("root", app.search_input.?.text());
    try std.testing.expect(app.search.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 1), app.search.results.len);
    try std.testing.expectEqual(@as(u64, 7), app.search_request_id);
}

test "loaded search results receive activation on search results screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .search_results;
    app.search_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    try app.search.setLoaded(std.testing.allocator, results);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?;
    try std.testing.expect(msg == .search_list);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 0 }, msg.search_list);
}

test "loaded collection receives activation on collection screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN"), .owned = true };

    try app.collection.setLoaded(std.testing.allocator, items);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?;
    try std.testing.expect(msg == .collection_list);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 0 }, msg.collection_list);
}

test "loaded collection slash starts filter" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };
    try app.collection.setLoaded(std.testing.allocator, items);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = '/' } }).?;
    try std.testing.expect(msg == .collection_filter_start);
}

test "collection filter maps visible activation back to source item" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "search results escape returns to search input screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .search_results;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expectEqual(App.Msg{ .show_screen = .search }, msg);
}

test "game detail escape returns to previous list screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .game_detail;
    app.detail_back_screen = .search_results;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expectEqual(App.Msg{ .show_screen = .search_results }, msg);
}

test "game detail view hides cursor left by previous screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});

    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(90, 24);
    defer ts.deinit();

    ts.surface.showCursor(4, 4);
    try std.testing.expect(ts.screen.cursor_vis);

    try app.viewGameDetail(&ts.surface);

    try std.testing.expect(!ts.screen.cursor_vis);
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

test "collection item labels omit status marker for Go compatibility" {
    const label = try formatCollectionItemLabel(std.testing.allocator, .{
        .id = 13,
        .name = "CATAN",
        .year_published = 1995,
        .num_plays = 3,
        .rating = 7.0,
        .bgg_rating = 6.5,
        .rank = 1,
        .owned = true,
    });
    defer std.testing.allocator.free(label);

    try std.testing.expectEqualStrings("CATAN (1995)  user 7.0  BGG 6.5  rank #1  plays 3", label);
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

test "hot games filter maps visible focus back to source index" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expect(state.filter_active);
    try std.testing.expectEqual(@as(usize, 2), state.filter.labels.len);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "hot games name sort preserves source index activation" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try std.testing.expectEqual(ListSortMode.name_asc, state.sort_mode);
    try std.testing.expectEqualStrings("# 2  Cascadia", state.activeList().items[0]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
}

test "hot games sorted projection owns movement and activation" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 0), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 1 }, state.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?);
}

test "hot games sort failure keeps existing projection state" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, state.toggleSort(failing_allocator.allocator()));

    try std.testing.expectEqual(ListSortMode.source, state.sort_mode);
    try std.testing.expectEqual(@as(usize, 0), state.sorted_source_indexes.len);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().items.len);
    try std.testing.expectEqualStrings("# 1  Root", state.activeList().items[0]);
}

test "hot games filter uses current name sort order" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 3);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    games[2] = .{ .id = 3, .rank = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try state.applyFilter(std.testing.allocator, "ca");

    try std.testing.expectEqualStrings("# 2  Cascadia", state.activeList().items[0]);
    try std.testing.expectEqualStrings("# 3  CATAN", state.activeList().items[1]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(1).?);
}

test "hot games slash starts filter before global search shortcut" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .hot_games;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = '/' } }).?;

    try std.testing.expect(msg == .hot_filter_start);
}

test "hot games global shortcuts work after clearing filter" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    app.hot_filter_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "ca" });
    defer app.deinitOwnedState();

    try app.hot_games.applyFilter(std.testing.allocator, "");
    const clear_msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(clear_msg == .hot_filter_clear);

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.update(clear_msg, &tc.ctx);

    const menu_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'm' } }).?;
    try std.testing.expectEqual(App.Msg{ .show_screen = .main_menu }, menu_msg);
}

test "search result labels include optional year" {
    const with_year = try formatSearchResultLabel(std.testing.allocator, .{
        .id = 13,
        .name = "CATAN",
        .year_published = 1995,
    });
    defer std.testing.allocator.free(with_year);

    const without_year = try formatSearchResultLabel(std.testing.allocator, .{
        .id = 42,
        .name = "No Year",
    });
    defer std.testing.allocator.free(without_year);

    try std.testing.expectEqualStrings("CATAN (1995)", with_year);
    try std.testing.expectEqualStrings("No Year", without_year);
}

test "search state owns labels for loaded results" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 2);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "First") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Second"), .year_published = 2024 };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 2), state.list.items.len);
    try std.testing.expectEqualStrings("First", state.list.items[0]);
    try std.testing.expectEqualStrings("Second (2024)", state.list.items[1]);
}

test "search results filter maps visible focus back to source index" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expect(state.filter_active);
    try std.testing.expectEqual(@as(usize, 2), state.filter.labels.len);
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "search results name sort preserves source index activation" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    try std.testing.expectEqual(ListSortMode.name_asc, state.sort_mode);
    try std.testing.expectEqualStrings("Cascadia", state.activeList().items[0]);
    try std.testing.expectEqual(@as(usize, 1), state.sourceIndex(0).?);
}

test "search results sorted projection owns movement and activation" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 3);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    results[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    try state.toggleSort(std.testing.allocator);
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 0), state.list.focusedIndex());
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 1 }, state.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?);
}

test "search results sort failure keeps existing projection state" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, state.toggleSort(failing_allocator.allocator()));

    try std.testing.expectEqual(ListSortMode.source, state.sort_mode);
    try std.testing.expectEqual(@as(usize, 0), state.sorted_source_indexes.len);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().items.len);
    try std.testing.expectEqualStrings("Root", state.activeList().items[0]);
}

test "search results slash starts filter" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .search_results;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = '/' } }).?;

    try std.testing.expect(msg == .search_filter_start);
}

test "successful search completion loads result list" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.search_request_id = 7;
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    try app.finishSearch(.{
        .request_id = 7,
        .result = .{ .ok = results },
    });

    try std.testing.expectEqual(@as(usize, 1), app.search.list.items.len);
}

test "failed search completion clears previous loaded results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };
    try app.search.setLoaded(std.testing.allocator, results);

    app.search_request_id = 3;
    try app.finishSearch(.{
        .request_id = 3,
        .result = .{ .failed = "rate limited" },
    });

    try std.testing.expect(app.search.load_state == .failed);
    try std.testing.expectEqual(@as(usize, 0), app.search.results.len);
    try std.testing.expectEqual(@as(usize, 0), app.search.labels.len);
    try std.testing.expectEqual(@as(usize, 0), app.search.list.items.len);
}

test "search loading clears previous loaded results" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    state.setLoading(std.testing.allocator);

    try std.testing.expect(state.load_state == .loading);
    try std.testing.expectEqual(@as(usize, 0), state.results.len);
    try std.testing.expectEqual(@as(usize, 0), state.labels.len);
    try std.testing.expectEqual(@as(usize, 0), state.list.items.len);
}

test "game detail state owns loaded game result" {
    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "CATAN"),
        .description = try std.testing.allocator.dupe(u8, "Trade, build, settle."),
    };

    var state: GameDetailState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 1), state.games.len);
    try std.testing.expectEqualStrings("CATAN", state.games[0].name);
}

test "outdated search results do not replace current search state" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.search_request_id = 2;

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    try app.finishSearch(.{
        .request_id = 1,
        .result = .{ .ok = results },
    });

    try std.testing.expect(app.search.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.search.list.items.len);
}

test "invalid search submit invalidates in-flight search results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.search_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "go" });
    defer app.deinitOwnedState();

    app.search_request_id = 1;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startSearch(&tc.ctx);

    try std.testing.expectEqual(@as(u64, 2), app.search_request_id);
    try std.testing.expect(app.search.load_state == .failed);

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    try app.finishSearch(.{
        .request_id = 1,
        .result = .{ .ok = results },
    });

    try std.testing.expect(app.search.load_state == .failed);
    try std.testing.expectEqual(@as(usize, 0), app.search.list.items.len);
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

test "constrained list surface clamps to max size" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(120, 40);
    defer ts.deinit();

    const area = constrainedListSurface(&ts.surface);

    try std.testing.expectEqual(list_screen_max_size.width, area.size().width);
    try std.testing.expectEqual(list_screen_max_size.height, area.size().height);
}

test "constrained list surface shrinks for small terminals" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(40, 12);
    defer ts.deinit();

    const area = constrainedListSurface(&ts.surface);

    try std.testing.expectEqual(@as(u16, 40), area.size().width);
    try std.testing.expectEqual(@as(u16, 12), area.size().height);
}
