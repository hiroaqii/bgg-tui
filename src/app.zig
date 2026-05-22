const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_client = @import("bgg/client.zig");
const bgg_endpoint = @import("bgg/endpoint.zig");
const bgg_error = @import("bgg/error.zig");
const bgg_model = @import("bgg/model.zig");
const bgg_xml = @import("bgg/xml.zig");
const browser = @import("browser.zig");
const config_mod = @import("config.zig");
const format = @import("format.zig");
const labels_mod = @import("labels.zig");
const list_filter = @import("list_filter.zig");
const list_view = @import("list_view.zig");
const motion = @import("motion.zig");
const screens = @import("screens/root.zig");
const style_mod = @import("style.zig");

// Keep top-level screens centered until a screen needs its own full-page layout.
const main_menu_size = chasen.Size{ .width = 48, .height = 12 };
const setup_token_size = chasen.Size{ .width = 56, .height = 9 };
const placeholder_size = chasen.Size{ .width = 56, .height = 6 };
const search_input_size = chasen.Size{ .width = 56, .height = 9 };
const collection_input_size = chasen.Size{ .width = 56, .height = 9 };
const list_screen_max_size = chasen.Size{ .width = 72, .height = 34 };
const forum_screen_max_size = chasen.Size{ .width = 88, .height = 34 };
const detail_outer_reserved_rows: u16 = 3;
const thread_outer_reserved_rows: u16 = 3;

// List screens follow the Go version's vertical rhythm:
// row 0 title, row 1 blank, row 2 position, row 3 blank, row 4 list body.
const list_position_row: u16 = 2;
const list_body_row: u16 = 4;
const list_footer_gap: u16 = 1;
const list_filter_row: u16 = 4;
const list_filtered_body_row: u16 = 6;
const collection_status_bar_row: u16 = 3;
const collection_body_row: u16 = 5;
const collection_status_picker_gap: u16 = 1;
const collection_status_picker_lines: u16 = 10;
const main_menu_shortcut_col: u16 = 24;

const collection_status_labels = [_][]const u8{
    "Owned",
    "Prev owned",
    "For trade",
    "Want",
    "Want to play",
    "Want to buy",
    "Wishlist",
    "Preordered",
};
const collection_picker_clear_index: usize = collection_status_labels.len;

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
    forums,
    thread,
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
    settings_token_input: ?ui.PasswordInput = null,
    settings_username_input: ?ui.TextInput = null,
    settings_width_input: ?ui.TextInput = null,
    owned_token: ?[]u8 = null,
    owned_default_username: ?[]u8 = null,
    hot_games: HotGamesState = .{},
    search: SearchState = .{},
    search_request_id: u64 = 0,
    collection: CollectionState = .{},
    collection_request_id: u64 = 0,
    collection_status_picker: bool = false,
    collection_status_cursor: usize = 0,
    collection_status_mask: u8 = 0,
    game_detail: screens.detail.State = .{},
    detail_request_id: u64 = 0,
    detail_back_screen: Screen = .main_menu,
    forums: screens.forum.State = .{},
    forum_request_id: u64 = 0,
    thread_list_request_id: u64 = 0,
    thread: screens.thread.State = .{},
    thread_request_id: u64 = 0,
    browser_request_id: u64 = 0,
    settings: screens.settings.State = .{},
    terminal_size: chasen.Size = forum_screen_max_size,
    menu: ui.Menu = ui.Menu.init(.{ .items = &menu_items }),
    animation_frame: u64 = 0,
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
        collection_change_user,
        collection_refresh,
        collection_status_open,
        collection_status_move_prev,
        collection_status_move_next,
        collection_status_toggle,
        collection_status_close,
        collection_items_loaded: CollectionTaskResult,
        collection_list: ui.List.Msg,
        game_detail_loaded: GameDetailTaskResult,
        game_detail_move_prev,
        game_detail_move_next,
        game_detail_open_browser,
        forum_open,
        forums_loaded: ForumListTaskResult,
        forum_list: ui.List.Msg,
        forum_threads_loaded: ForumThreadsTaskResult,
        forum_thread_list: ui.List.Msg,
        forum_back_to_detail,
        forum_back_to_list,
        forum_next_page,
        forum_previous_page,
        thread_open: usize,
        thread_loaded: ThreadTaskResult,
        thread_move_prev,
        thread_move_next,
        thread_sort_toggle,
        thread_open_browser,
        browser_opened: BrowserOpenTaskResult,
        thread_back_to_forums,
        settings_token_start,
        settings_token_input: ui.PasswordInput.Msg,
        settings_token_paste: []const u8,
        settings_token_submit,
        settings_token_cancel,
        settings_username_start,
        settings_username_input: ui.TextInput.Msg,
        settings_username_paste: []const u8,
        settings_username_submit,
        settings_username_cancel,
        settings_width_start: screens.settings.EditField,
        settings_width_input: ui.TextInput.Msg,
        settings_width_paste: []const u8,
        settings_width_submit,
        settings_width_cancel,
        settings_show_images_toggle,
        settings_cycle_next: screens.settings.CycleField,
        settings_list: ui.List.Msg,
        terminal_resized: chasen.Size,
        frame: chasen.Frame,
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
            .collection_status_mask = config.collection.status_filter.mask,
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
        self.settings_token_input = try ui.PasswordInput.init(ctx.allocator(), .{
            .placeholder = "Enter API token",
        });
        self.settings_username_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Enter BGG username",
        });
        self.settings_width_input = try ui.TextInput.init(ctx.allocator(), .{
            .placeholder = "Enter width (20-240)",
        });
        self.requestSelectionFrameIfNeeded(ctx);
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
            .collection_change_user => try self.changeCollectionUser(),
            .collection_refresh => try self.refreshCollection(ctx),
            .collection_status_open => self.openCollectionStatusPicker(),
            .collection_status_move_prev => self.moveCollectionStatusCursor(.prev),
            .collection_status_move_next => self.moveCollectionStatusCursor(.next),
            .collection_status_toggle => try self.toggleCollectionStatus(ctx),
            .collection_status_close => self.collection_status_picker = false,
            .collection_items_loaded => |result| try self.finishCollectionLoad(result),
            .collection_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.collection.update(list_msg),
                .activate => |index| {
                    if (self.collection.sourceIndex(index)) |source_index| try self.openCollectionItem(source_index, ctx);
                },
            },
            .game_detail_loaded => |result| try self.finishGameDetail(result),
            .game_detail_move_prev => self.game_detail.moveUp(),
            .game_detail_move_next => self.game_detail.moveDown(self.game_detail.visible_height),
            .game_detail_open_browser => try self.openGameInBrowser(ctx),
            .forum_open => try self.startForumList(ctx),
            .forums_loaded => |result| try self.finishForumList(result),
            .forum_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.forums.updateForumList(list_msg),
                .activate => |index| try self.startForumThreads(ctx, index, 1),
            },
            .forum_threads_loaded => |result| try self.finishForumThreads(result),
            .forum_thread_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.forums.updateThreadList(list_msg),
                .activate => |index| try self.startThread(ctx, index),
            },
            .forum_back_to_detail => try self.showScreen(.game_detail, ctx),
            .forum_back_to_list => self.backToForumList(),
            .forum_next_page => try self.openForumPage(ctx, self.forums.thread_page.page + 1),
            .forum_previous_page => try self.openForumPage(ctx, self.forums.thread_page.page -| 1),
            .thread_open => |index| try self.startThread(ctx, index),
            .thread_loaded => |result| try self.finishThread(result),
            .thread_move_prev => self.thread.moveUp(),
            .thread_move_next => self.thread.moveDown(threadLayoutForTerminal(self).content_height),
            .thread_sort_toggle => try self.thread.toggleSort(self.allocator.?),
            .thread_open_browser => try self.openThreadInBrowser(ctx),
            .browser_opened => |result| try self.finishBrowserOpen(result),
            .thread_back_to_forums => self.backToThreadList(),
            .settings_token_start => try self.startSettingsTokenEdit(),
            .settings_token_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsToken(ctx);
                } else if (self.settings_token_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .settings_token_paste => |text| {
                if (self.settings_token_input) |*input| {
                    try insertPastedCodepoints(input, text);
                }
            },
            .settings_token_submit => try self.submitSettingsToken(ctx),
            .settings_token_cancel => self.cancelSettingsTokenEdit(),
            .settings_username_start => try self.startSettingsUsernameEdit(),
            .settings_username_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsUsername(ctx);
                } else if (self.settings_username_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .settings_username_paste => |text| {
                if (self.settings_username_input) |*input| {
                    try insertPastedCodepoints(input, text);
                }
            },
            .settings_username_submit => try self.submitSettingsUsername(ctx),
            .settings_username_cancel => self.cancelSettingsUsernameEdit(),
            .settings_width_start => |field| try self.startSettingsWidthEdit(field),
            .settings_width_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsWidth(ctx);
                } else if (self.settings_width_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .settings_width_paste => |text| {
                if (self.settings_width_input) |*input| {
                    try insertPastedCodepoints(input, text);
                }
            },
            .settings_width_submit => try self.submitSettingsWidth(ctx),
            .settings_width_cancel => self.cancelSettingsWidthEdit(),
            .settings_show_images_toggle => try self.toggleSettingsShowImages(ctx),
            .settings_cycle_next => |field| try self.cycleSettingsField(ctx, field),
            .settings_list => |list_msg| self.settings.updateList(list_msg),
            .terminal_resized => |size| self.handleResize(size),
            .frame => |frame| {
                self.animation_frame = frame.index;
                self.requestSelectionFrameIfNeeded(ctx);
            },
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
        const shell_frame = ui.Panel.frame(&shell_area, .{
            .title = "BoardGameGeek",
            .border = self.panelBorder(),
            .border_style = self.theme().border,
            .title_style = self.theme().title,
        });
        shell_frame.view();

        var body_area = shell_frame.contentSurface();
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
        if (event == .frame) return .{ .frame = event.frame };
        if (event == .winsize) {
            return .{ .terminal_resized = .{ .width = event.winsize.cols, .height = event.winsize.rows } };
        }

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
                    if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .game_detail_move_prev;
                    if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .game_detail_move_next;
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .{ .show_screen = self.detail_back_screen };
                    if (key.codepoint == 'f' and self.game_detail.load_state == .loaded and self.game_detail.games.len > 0) return .forum_open;
                    if (key.codepoint == 'o' and self.game_detail.load_state == .loaded and self.game_detail.games.len > 0) return .game_detail_open_browser;
                    if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.codepoint == 'q') return .quit;
                },
                else => {},
            }
            return null;
        }

        if (self.screen == .forums) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.codepoint == 'q') return .quit;
                    if (key.codepoint == 'b') {
                        return if (self.forums.mode == .thread_list) .forum_back_to_list else .forum_back_to_detail;
                    }
                    if (self.forums.mode == .thread_list) {
                        if (key.codepoint == 'n' and self.forums.canOpenNextPage()) return .forum_next_page;
                        if (key.codepoint == 'p' and self.forums.canOpenPreviousPage()) return .forum_previous_page;
                        if (self.forums.thread_list.handleEvent(event)) |msg| return .{ .forum_thread_list = msg };
                    } else if (self.forums.mode == .forum_list) {
                        if (self.forums.forum_list.handleEvent(event)) |msg| return .{ .forum_list = msg };
                    }
                },
                else => {},
            }
            return null;
        }

        if (self.screen == .thread) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.codepoint == 'q') return .quit;
                    if (key.codepoint == 'b') return .thread_back_to_forums;
                    if (self.thread.load_state == .loaded) {
                        if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .thread_move_prev;
                        if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .thread_move_next;
                        if (key.codepoint == 's') return .thread_sort_toggle;
                        if (key.codepoint == 'o') return .thread_open_browser;
                    }
                },
                else => {},
            }
            return null;
        }

        if (self.screen == .collection) {
            if (self.collection_status_picker) {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) return .collection_status_close;
                        if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .collection_status_move_prev;
                        if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .collection_status_move_next;
                        if (key.matches(chasen.Key.enter, .{})) return .collection_status_toggle;
                    },
                    else => {},
                }
                return null;
            }
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
                        if (key.codepoint == 's') return .collection_status_open;
                        if (key.codepoint == '/') return .collection_filter_start;
                        if (key.codepoint == 'u') return .collection_change_user;
                        if (key.codepoint == 'r') return .collection_refresh;
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

        if (self.screen == .settings) {
            if (self.settings.editing) |field| {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) {
                            return switch (field) {
                                .token => .settings_token_cancel,
                                .username => .settings_username_cancel,
                                .list_width, .thread_width, .detail_width => .settings_width_cancel,
                            };
                        }
                        if (key.matches(chasen.Key.enter, .{})) {
                            return switch (field) {
                                .token => .settings_token_submit,
                                .username => .settings_username_submit,
                                .list_width, .thread_width, .detail_width => .settings_width_submit,
                            };
                        }
                    },
                    .paste => |text| {
                        return switch (field) {
                            .token => .{ .settings_token_paste = text },
                            .username => .{ .settings_username_paste = text },
                            .list_width, .thread_width, .detail_width => .{ .settings_width_paste = text },
                        };
                    },
                    else => {},
                }
                switch (field) {
                    .token => if (self.settings_token_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings_token_input = msg };
                    },
                    .username => if (self.settings_username_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings_username_input = msg };
                    },
                    .list_width, .thread_width, .detail_width => if (self.settings_width_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings_width_input = msg };
                    },
                }
                return null;
            }
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.enter, .{})) {
                        if (self.settings.isShowImagesFocused()) return .settings_show_images_toggle;
                        if (self.settings.focusedCycleField()) |field| return .{ .settings_cycle_next = field };
                        if (self.settings.focusedEditField()) |field| {
                            return switch (field) {
                                .token => .settings_token_start,
                                .username => .settings_username_start,
                                .list_width, .thread_width, .detail_width => .{ .settings_width_start = field },
                            };
                        }
                    }
                    if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'q') return .quit;
                },
                else => {},
            }
            if (self.settings.handleEvent(event)) |msg| return .{ .settings_list = msg };
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
            .forums => try self.viewForums(sfc),
            .thread => try self.viewThread(sfc),
            .collection => try self.viewCollection(sfc),
            .settings => try self.viewSettings(sfc),
        }
    }

    fn viewSetupToken(self: *const App, sfc: *chasen.Surface) void {
        var area = centeredSurface(sfc, setup_token_size);
        _ = area.borrowTextAt(0, 0, "Setup BGG API token", self.titleStyle());
        _ = area.borrowTextAt(0, 2, "BGG API access requires a token.", self.mutedStyle());
        _ = area.borrowTextAt(0, 3, "Enter a token to continue to the main menu.", self.mutedStyle());

        if (self.setup_token_input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 5, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        _ = area.borrowTextAt(0, 7, setupTokenSubmitHint(self.config_path), self.subtleStyle());
    }

    fn viewMainMenu(self: *const App, sfc: *chasen.Surface) !void {
        var area = centeredSurface(sfc, main_menu_size);
        const token_status = if (self.config.apiClientToken() == null) "missing" else "configured";
        ui.message_block.drawCenteredText(&area, 0, "Main menu", self.titleStyle());
        const token_text = try std.fmt.allocPrint(area.frameAllocator(), "BGG API token: {s}", .{token_status});
        ui.message_block.drawCenteredText(&area, 2, token_text, self.mutedStyle());

        const menu_width = mainMenuContentWidth();
        const menu_col: u16 = if (menu_width >= area.size().width) 0 else @intCast((area.size().width - menu_width) / 2);
        var menu_area = area.child(.{
            .col = menu_col,
            .row = 4,
            .width = @min(area.size().width, menu_width),
            .height = @min(area.size().height -| 4, @as(u16, menu_items.len)),
        });
        self.menu.view(&menu_area, .{
            .shortcut_col = main_menu_shortcut_col,
            .focused_style = self.focusedStyle(),
        });

        ui.message_block.drawCenteredText(&area, 10, self.footerHint(), self.subtleStyle());
    }

    fn viewPlaceholder(self: *const App, sfc: *chasen.Surface, title: []const u8, message: []const u8) void {
        var area = centeredSurface(sfc, placeholder_size);
        _ = area.borrowTextAt(0, 0, title, self.titleStyle());
        _ = area.borrowTextAt(0, 2, message, self.mutedStyle());
        _ = area.borrowTextAt(0, 4, self.footerHint(), self.subtleStyle());
    }

    fn viewSettings(self: *const App, sfc: *chasen.Surface) !void {
        var area = centeredSurface(sfc, screens.settings.required_size);
        const token_input = if (self.settings_token_input) |*input| input else null;
        const username_input = if (self.settings_username_input) |*input| input else null;
        const width_input = if (self.settings_width_input) |*input| input else null;
        try self.settings.view(&area, self.config, self.config_path, self.theme(), token_input, username_input, width_input);
    }

    fn viewHotGames(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = try area.printAt(0, 0, self.titleStyle(), "Hot Games ({s})", .{self.hot_games.sort_mode.label(.hot_games)});

        switch (self.hot_games.load_state) {
            .idle, .loading => {
                self.drawCenteredGuidance(&area, "Hot Games", "Loading BoardGameGeek hot games...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load hot games.", message);
            },
            .loaded => {
                if (self.hot_games.list.items.len == 0) {
                    self.drawCenteredGuidance(&area, "No hot games", "BGG did not return any hot games.");
                } else if (self.hot_games.filter_active and self.hot_games.filter.labels.len == 0) {
                    try self.drawHotFilterInput(&area);
                    self.drawCenteredGuidanceKeepingCursor(&area, "No matches", "No hot games match the filter.");
                } else {
                    const body_row = if (self.hot_games.filter_active) list_filtered_body_row else list_body_row;
                    if (self.hot_games.filter_active) try self.drawHotFilterInput(&area);
                    const list = self.hot_games.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1 + list_footer_gap),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = self.focusedStyle(),
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                    self.drawSortMode(&area, self.hot_games.sort_mode.label(.hot_games));
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewSearch(self: *const App, sfc: *chasen.Surface) !void {
        var area = centeredSurface(sfc, search_input_size);
        _ = area.borrowTextAt(0, 0, "Search Games", self.titleStyle());

        if (self.search_input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 2, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        switch (self.search.load_state) {
            .idle => {
                self.drawGuidance(&area, 4, "Search board games", "Enter at least 3 characters and press Enter.");
            },
            .loading => {
                self.drawGuidance(&area, 4, "Search board games", "Search request is running...");
            },
            .failed => |message| {
                self.drawGuidance(&area, 4, "Could not search games.", message);
            },
            .loaded => {
                self.drawGuidance(&area, 4, "Search complete", "Press Enter to run a new search.");
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewSearchResults(self: *const App, sfc: *chasen.Surface) !void {
        var area = constrainedListSurface(sfc);
        _ = try area.printAt(0, 0, self.titleStyle(), "Search Results ({s})", .{self.search.sort_mode.label(.search_results)});

        switch (self.search.load_state) {
            .idle => {
                self.drawCenteredGuidance(&area, "No search yet", "Run a search to see matching board games.");
            },
            .loading => {
                self.drawCenteredGuidance(&area, "Search Results", "Searching BoardGameGeek...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not search games.", message);
            },
            .loaded => {
                if (self.search.list.items.len == 0) {
                    self.drawCenteredGuidance(&area, "No results", "No games matched the current query.");
                } else if (self.search.filter_active and self.search.filter.labels.len == 0) {
                    try self.drawSearchFilterInput(&area);
                    self.drawCenteredGuidanceKeepingCursor(&area, "No matches", "No search results match the filter.");
                } else {
                    const body_row = if (self.search.filter_active) list_filtered_body_row else list_body_row;
                    if (self.search.filter_active) try self.drawSearchFilterInput(&area);
                    const list = self.search.activeList();
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1 + list_footer_gap),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = self.focusedStyle(),
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                    self.drawSortMode(&area, self.search.sort_mode.label(.search_results));
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewCollection(self: *const App, sfc: *chasen.Surface) !void {
        var area = switch (self.collection.load_state) {
            .idle, .failed => centeredSurface(sfc, collection_input_size),
            else => constrainedListSurface(sfc),
        };
        _ = area.borrowTextAt(0, 0, "Collection", self.titleStyle());

        switch (self.collection.load_state) {
            .idle => {
                try self.drawCollectionUsernameInput(&area);
                self.drawGuidance(&area, 4, "Load collection", "Enter a BGG username and press Enter.");
            },
            .loading => {
                self.drawCenteredGuidance(&area, "Collection", "Loading BoardGameGeek collection...");
            },
            .failed => |message| {
                try self.drawCollectionUsernameInput(&area);
                self.drawGuidance(&area, 4, "Could not load collection.", message);
            },
            .loaded => {
                self.drawCollectionStatusBar(&area);
                if (self.collection.list.items.len == 0) {
                    if (self.collection.statusFilteredEmpty()) {
                        self.drawCenteredGuidance(&area, "No status matches", "No collection items match the selected statuses.");
                    } else {
                        self.drawCenteredGuidance(&area, "No collection items", "BGG did not return any games for this collection.");
                    }
                } else if (self.collection.filter_active and self.collection.filter.labels.len == 0) {
                    try self.drawCollectionFilterInput(&area);
                    self.drawCenteredGuidanceKeepingCursor(&area, "No matches", "No collection items match the filter.");
                } else {
                    const body_row = if (self.collection.filter_active) list_filtered_body_row else collection_body_row;
                    if (self.collection.filter_active) try self.drawCollectionFilterInput(&area);
                    const list = self.collection.activeList();
                    const picker_height = if (self.collection_status_picker) collection_status_picker_lines + collection_status_picker_gap else 0;
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (body_row + 1 + picker_height),
                    });
                    list_view.viewListWithDensity(list, &list_area, .{
                        .focused_style = self.focusedStyle(),
                    }, self.listDensity());
                    try self.drawListPosition(&area, list);
                }
                if (self.collection_status_picker) {
                    const picker_row = area.size().height -| (collection_status_picker_lines + 1);
                    self.drawCollectionStatusPicker(&area, @max(collection_body_row, picker_row));
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewGameDetail(self: *const App, sfc: *chasen.Surface) !void {
        sfc.hideCursor();
        var area = detailSurface(sfc, self.config.display.detail_width);

        switch (self.game_detail.load_state) {
            .idle, .loading => {
                self.drawCenteredGuidance(&area, "Game Details", "Loading game detail...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load game detail.", message);
            },
            .loaded => {
                const detail_layout = detailLayout(area.size().height, self.config.interface.list_density);
                if (self.game_detail.games.len == 0) {
                    self.drawEmptyState(&area, detail_layout.content_row, "No detail", "BGG did not return game detail.");
                } else {
                    const range = self.game_detail.visibleRange(detail_layout.content_height);
                    for (self.game_detail.lines[range.start..range.end], 0..) |line, index| {
                        const row = detail_layout.content_row + @as(u16, @intCast(index));
                        if (index >= detail_layout.content_height or row >= area.size().height) break;
                        _ = area.borrowTextAt(0, row, line, screens.detail.lineStyle(line));
                    }

                    if (self.game_detail.browser_error_url.len > 0) {
                        try self.drawManualOpenHint(&area, detail_layout.scroll_row, self.game_detail.browser_error_url);
                    } else if (self.game_detail.maxScroll(detail_layout.content_height) > 0 and area.size().height >= 3) {
                        _ = try area.printAt(0, detail_layout.scroll_row, .{ .dim = true }, "({d}/{d})", .{
                            self.game_detail.scroll + 1,
                            self.game_detail.maxScroll(detail_layout.content_height) + 1,
                        });
                    }
                }
            },
        }

        const detail_layout = detailLayout(area.size().height, self.config.interface.list_density);
        _ = area.borrowTextAt(0, detail_layout.footer_row, self.footerHint(), self.subtleStyle());
    }

    fn viewForums(self: *const App, sfc: *chasen.Surface) !void {
        var area = forumSurface(sfc);

        switch (self.forums.load_state) {
            .idle, .loading_forums => {
                const title = try std.fmt.allocPrint(area.frameAllocator(), "{s} - Forums", .{self.forums.game_name});
                self.drawCenteredGuidance(&area, title, "Loading BoardGameGeek forums...");
            },
            .forums_loaded => {
                if (self.forums.forum_list.items.len == 0) {
                    self.drawCenteredGuidance(&area, "No forums", "BGG did not return forums for this game.");
                } else {
                    var forum_area = forumListSurface(&area, self.forums.forum_list.items.len);
                    const title = try std.fmt.allocPrint(forum_area.frameAllocator(), "{s} - Forums", .{self.forums.game_name});
                    ui.message_block.drawCenteredText(&forum_area, 0, title, self.titleStyle());
                    try self.drawCenteredListPosition(&forum_area, &self.forums.forum_list);
                    try self.drawCenteredForumList(&forum_area);
                    ui.message_block.drawCenteredText(&forum_area, forum_area.size().height -| 1, self.footerHint(), self.subtleStyle());
                }
            },
            .loading_threads => {
                self.drawCenteredGuidance(&area, self.forumThreadTitle(), "Loading BoardGameGeek threads...");
            },
            .threads_loaded => {
                _ = area.borrowTextAt(0, 0, self.forumThreadTitle(), self.titleStyle());
                _ = try area.printAt(0, list_position_row, self.subtleStyle(), "Page {d} / {d}", .{ self.forums.thread_page.page, self.forums.thread_page.total_pages });
                if (self.forums.thread_list.items.len == 0) {
                    self.drawCenteredGuidance(&area, "No threads", "BGG did not return threads for this forum page.");
                } else {
                    var list_area = area.child(.{
                        .col = 0,
                        .row = list_body_row,
                        .width = area.size().width,
                        .height = area.size().height -| (list_body_row + 1),
                    });
                    try self.drawForumThreadList(&list_area);
                }
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load forums.", message);
            },
        }

        if (self.forums.load_state != .forums_loaded or self.forums.forum_list.items.len == 0) {
            _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
        }
    }

    fn viewThread(self: *const App, sfc: *chasen.Surface) !void {
        var area = threadSurface(sfc, self.config.display.thread_width);

        switch (self.thread.load_state) {
            .idle, .loading => {
                self.drawCenteredGuidance(&area, "Thread", "Loading thread...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load thread.", message);
            },
            .loaded => {
                const thread_layout = threadLayout(area.size().height, self.config.interface.list_density);
                _ = area.borrowTextAt(0, thread_layout.title_row, self.thread.subject(), self.titleStyle());
                _ = try area.printAt(0, thread_layout.meta_row, self.subtleStyle(), "{d} posts · {s}", .{ self.thread.postCount(), self.thread.sortLabel() });

                var body_area = area.child(.{
                    .col = 0,
                    .row = thread_layout.content_row,
                    .width = area.size().width,
                    .height = @intCast(@min(thread_layout.content_height, std.math.maxInt(u16))),
                });
                self.drawThreadBody(&body_area);

                if (self.thread.browser_error_url.len > 0) {
                    try self.drawManualOpenHint(&area, thread_layout.scroll_row, self.thread.browser_error_url);
                } else if (self.thread.maxScroll(thread_layout.content_height) > 0 and area.size().height >= 3) {
                    _ = try area.printAt(0, thread_layout.scroll_row, self.subtleStyle(), "({d}/{d})", .{
                        self.thread.scroll + 1,
                        self.thread.maxScroll(thread_layout.content_height) + 1,
                    });
                }
            },
        }

        const thread_layout = threadLayout(area.size().height, self.config.interface.list_density);
        _ = area.borrowTextAt(0, thread_layout.footer_row, self.footerHint(), self.subtleStyle());
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
        try self.saveConfigIfAvailable(ctx);
        try input.update(.clear);
        self.screen = .main_menu;
    }

    fn startSettingsTokenEdit(self: *App) !void {
        if (self.settings_token_input) |*input| {
            try input.update(.clear);
        }
        self.settings.startEdit(.token);
    }

    fn submitSettingsToken(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.settings_token_input) |*input| input else return;
        const token = std.mem.trim(u8, input.text(), " \t\r\n");
        if (token.len > 0) {
            if (self.owned_token) |old| self.allocator.?.free(old);
            self.owned_token = try self.allocator.?.dupe(u8, token);
            self.config.api.token = self.owned_token;
            try self.saveConfigIfAvailable(ctx);
        }
        try input.update(.clear);
        self.settings.stopEditing();
    }

    fn cancelSettingsTokenEdit(self: *App) void {
        if (self.settings_token_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn startSettingsUsernameEdit(self: *App) !void {
        if (self.settings_username_input) |*input| {
            try input.update(.clear);
            if (self.config.collection.default_username) |username| {
                try insertPastedCodepoints(input, username);
            }
        }
        self.settings.startEdit(.username);
    }

    fn submitSettingsUsername(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.settings_username_input) |*input| input else return;
        const username = std.mem.trim(u8, input.text(), " \t\r\n");
        if (username.len == 0) {
            if (self.owned_default_username) |old| self.allocator.?.free(old);
            self.owned_default_username = null;
            self.config.collection.default_username = null;
        } else {
            if (self.owned_default_username) |old| self.allocator.?.free(old);
            const owned_username = try self.allocator.?.dupe(u8, username);
            self.owned_default_username = owned_username;
            self.config.collection.default_username = owned_username;
        }
        try self.saveConfigIfAvailable(ctx);
        try input.update(.clear);
        self.settings.stopEditing();
    }

    fn cancelSettingsUsernameEdit(self: *App) void {
        if (self.settings_username_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn startSettingsWidthEdit(self: *App, field: screens.settings.EditField) !void {
        if (self.settings_width_input) |*input| {
            try input.update(.clear);
            try inputWidthValue(input, self.config, field);
        }
        self.settings.startEdit(field);
    }

    fn submitSettingsWidth(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const field = self.settings.editing orelse return;
        const input = if (self.settings_width_input) |*input| input else return;
        const value = parseSettingsWidth(input.text()) catch return;
        switch (field) {
            .list_width => self.config.display.list_width = value,
            .thread_width => self.config.display.thread_width = value,
            .detail_width => self.config.display.detail_width = value,
            else => return,
        }
        try self.saveConfigIfAvailable(ctx);
        try input.update(.clear);
        self.settings.stopEditing();
    }

    fn cancelSettingsWidthEdit(self: *App) void {
        if (self.settings_width_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn toggleSettingsShowImages(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.config.display.show_images = !self.config.display.show_images;
        try self.saveConfigIfAvailable(ctx);
    }

    fn cycleSettingsField(self: *App, ctx: *chasen.Ctx(Msg), field: screens.settings.CycleField) !void {
        switch (field) {
            .color_theme => self.config.interface.color_theme = nextCycleValue(self.config.interface.color_theme, &color_theme_values),
            .transition => self.config.interface.transition = nextCycleValue(self.config.interface.transition, &transition_values),
            .selection => {
                self.config.interface.selection = nextCycleValue(self.config.interface.selection, &selection_values);
                self.requestSelectionFrameIfNeeded(ctx);
            },
            .border_style => self.config.interface.border_style = nextCycleValue(self.config.interface.border_style, &border_style_values),
            .list_density => self.config.interface.list_density = nextCycleValue(self.config.interface.list_density, &list_density_values),
            .date_format => self.config.interface.date_format = nextCycleValue(self.config.interface.date_format, &date_format_values),
            .image_protocol => self.config.display.image_protocol = nextImageProtocol(self.config.display.image_protocol),
        }
        try self.saveConfigIfAvailable(ctx);
    }

    fn saveConfigIfAvailable(self: *const App, ctx: *chasen.Ctx(Msg)) !void {
        const path = self.config_path orelse return;
        try config_mod.saveConfig(ctx.allocator(), ctx.io(), path, self.config);
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
        if (self.settings_token_input) |*input| {
            input.deinit();
            self.settings_token_input = null;
        }
        if (self.settings_username_input) |*input| {
            input.deinit();
            self.settings_username_input = null;
        }
        if (self.settings_width_input) |*input| {
            input.deinit();
            self.settings_width_input = null;
        }
        if (self.owned_token) |token| {
            self.allocator.?.free(token);
            self.owned_token = null;
        }
        if (self.owned_default_username) |username| {
            self.allocator.?.free(username);
            self.owned_default_username = null;
        }
        self.hot_games.deinit(self.allocator.?);
        self.search.deinit(self.allocator.?);
        self.collection.deinit(self.allocator.?);
        self.game_detail.deinit(self.allocator.?);
        self.forums.deinit(self.allocator.?);
        self.thread.deinit(self.allocator.?);
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

    fn changeCollectionUser(self: *App) !void {
        self.collection_request_id +%= 1;
        self.collection_status_picker = false;
        if (self.collection_filter_input) |*input| try input.update(.clear);
        self.collection.deinit(self.allocator.?);
    }

    fn refreshCollection(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.collection_filter_input) |*input| try input.update(.clear);
        self.collection.clearFilter(self.allocator.?);
        try self.startCollectionLoad(ctx);
    }

    const StatusMove = enum { prev, next };

    fn openCollectionStatusPicker(self: *App) void {
        self.collection_status_picker = true;
        self.collection_status_cursor = 0;
    }

    fn moveCollectionStatusCursor(self: *App, direction: StatusMove) void {
        switch (direction) {
            .prev => {
                if (self.collection_status_cursor > 0) self.collection_status_cursor -= 1;
            },
            .next => {
                if (self.collection_status_cursor < collection_picker_clear_index) self.collection_status_cursor += 1;
            },
        }
    }

    fn toggleCollectionStatus(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.collection_status_cursor == collection_picker_clear_index) {
            self.collection_status_mask = 0;
        } else {
            const bit = collectionStatusBit(self.collection_status_cursor);
            if ((self.collection_status_mask & bit) != 0) {
                self.collection_status_mask &= ~bit;
            } else {
                self.collection_status_mask |= bit;
            }
        }
        self.config.collection.status_filter.mask = self.collection_status_mask;
        try self.saveConfigIfAvailable(ctx);
        try self.collection.applyStatusFilter(self.allocator.?, self.collection_status_mask);
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
            .ok => |items| try self.collection.setLoaded(self.allocator.?, items, self.collection_status_mask),
            .failed => |message| self.collection.setFailed(self.allocator.?, message),
        }
    }

    fn startGameDetail(self: *App, ctx: *chasen.Ctx(Msg), game_id: u32, back_screen: Screen) !void {
        self.detail_request_id +%= 1;
        self.browser_request_id +%= 1;
        const request_id = self.detail_request_id;
        self.detail_back_screen = back_screen;
        self.screen = .game_detail;
        self.game_detail.deinit(self.allocator.?);
        self.game_detail.setVisibleHeight(detailLayoutForTerminal(self).content_height);

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
            .ok => |games| {
                try self.game_detail.setLoaded(self.allocator.?, games, self.config.display.detail_width);
                self.game_detail.setVisibleHeight(detailLayoutForTerminal(self).content_height);
            },
            .failed => |message| self.game_detail.setFailed(message),
        }
    }

    fn openGameInBrowser(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.game_detail.load_state != .loaded or self.game_detail.games.len == 0) return;

        const game = self.game_detail.games[0];
        const url = try formatOwnedText(ctx.allocator(), format.writeBggGameUrl, .{game.id});
        errdefer ctx.allocator().free(url);

        self.browser_request_id +%= 1;
        const request_id = self.browser_request_id;

        const task = try ctx.allocator().create(BrowserOpenTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{ .url = url, .request_id = request_id, .target = .game_detail };

        ctx.spawnWith(task, BrowserOpenTask.run) catch |err| {
            ctx.allocator().free(url);
            return err;
        };
    }

    fn startForumList(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.game_detail.load_state != .loaded or self.game_detail.games.len == 0) return;
        const game = self.game_detail.games[0];
        self.forum_request_id +%= 1;
        self.thread_list_request_id +%= 1;
        const request_id = self.forum_request_id;

        try self.forums.startForumLoad(self.allocator.?, game.id, game.name);
        self.screen = .forums;

        const token = self.config.apiClientToken() orelse {
            self.forums.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(ForumListTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .game_id = game.id,
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.token);

        ctx.spawnWith(task, ForumListTask.run) catch |err| {
            self.forums.setFailed("Could not start forum loading task");
            return err;
        };
    }

    fn finishForumList(self: *App, task_result: ForumListTaskResult) !void {
        if (task_result.request_id != self.forum_request_id) {
            switch (task_result.result) {
                .ok => |forums| bgg_xml.freeForums(self.allocator.?, forums),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |forums| try self.forums.setForumsLoaded(self.allocator.?, forums),
            .failed => |message| self.forums.setFailed(message),
        }
    }

    fn startForumThreads(self: *App, ctx: *chasen.Ctx(Msg), visible_index: usize, page: u32) !void {
        const forum = self.forums.selectedForumFromVisible(visible_index) orelse return;
        self.thread_list_request_id +%= 1;
        const request_id = self.thread_list_request_id;
        self.forums.startThreadLoad(self.allocator.?, visible_index);
        try self.spawnForumThreadsTask(ctx, forum.id, page, request_id);
    }

    fn openForumPage(self: *App, ctx: *chasen.Ctx(Msg), page: u32) !void {
        const forum = self.forums.selectedForum() orelse return;
        self.thread_list_request_id +%= 1;
        const request_id = self.thread_list_request_id;
        self.forums.startThreadPageLoad(self.allocator.?, page);
        try self.spawnForumThreadsTask(ctx, forum.id, page, request_id);
    }

    fn spawnForumThreadsTask(self: *App, ctx: *chasen.Ctx(Msg), forum_id: u32, page: u32, request_id: u64) !void {
        const token = self.config.apiClientToken() orelse {
            self.forums.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(ForumThreadsTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .forum_id = forum_id,
            .page = page,
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.token);

        ctx.spawnWith(task, ForumThreadsTask.run) catch |err| {
            self.forums.setFailed("Could not start thread list loading task");
            return err;
        };
    }

    fn finishForumThreads(self: *App, task_result: ForumThreadsTaskResult) !void {
        if (task_result.request_id != self.thread_list_request_id) {
            switch (task_result.result) {
                .ok => |thread_page| bgg_xml.freeThreadList(self.allocator.?, thread_page),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |thread_page| try self.forums.setThreadsLoaded(self.allocator.?, thread_page),
            .failed => |message| self.forums.setFailed(message),
        }
    }

    fn backToForumList(self: *App) void {
        self.thread_list_request_id +%= 1;
        self.forums.backToForumList(self.allocator.?);
    }

    fn startThread(self: *App, ctx: *chasen.Ctx(Msg), visible_index: usize) !void {
        if (visible_index >= self.forums.thread_page.threads.len) return;
        const thread = self.forums.thread_page.threads[visible_index];
        self.thread_request_id +%= 1;
        self.browser_request_id +%= 1;
        const request_id = self.thread_request_id;

        self.thread.startLoad(self.allocator.?, thread.id, self.config.display.thread_width);
        self.thread.setVisibleHeight(threadLayoutForTerminal(self).content_height);
        self.screen = .thread;

        const token = self.config.apiClientToken() orelse {
            self.thread.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(ThreadTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .thread_id = thread.id,
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.token);

        ctx.spawnWith(task, ThreadTask.run) catch |err| {
            self.thread.setFailed("Could not start thread loading task");
            return err;
        };
    }

    fn finishThread(self: *App, task_result: ThreadTaskResult) !void {
        if (task_result.request_id != self.thread_request_id) {
            switch (task_result.result) {
                .ok => |thread| bgg_xml.freeThread(self.allocator.?, thread),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |thread| try self.thread.setLoaded(self.allocator.?, thread),
            .failed => |message| self.thread.setFailed(message),
        }
    }

    fn backToThreadList(self: *App) void {
        self.thread_request_id +%= 1;
        self.browser_request_id +%= 1;
        self.thread.deinit(self.allocator.?);
        self.screen = .forums;
    }

    fn openThreadInBrowser(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.thread.load_state != .loaded or self.thread.thread_id == 0) return;

        const url = try formatOwnedText(ctx.allocator(), format.writeBggThreadUrl, .{self.thread.thread_id});
        errdefer ctx.allocator().free(url);

        self.browser_request_id +%= 1;
        const request_id = self.browser_request_id;

        const task = try ctx.allocator().create(BrowserOpenTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{ .url = url, .request_id = request_id, .target = .thread };

        ctx.spawnWith(task, BrowserOpenTask.run) catch |err| {
            ctx.allocator().free(url);
            return err;
        };
    }

    fn finishBrowserOpen(self: *App, task_result: BrowserOpenTaskResult) !void {
        if (task_result.request_id != self.browser_request_id) {
            switch (task_result.result) {
                .ok => {},
                .failed => |url| self.allocator.?.free(url),
            }
            return;
        }

        switch (task_result.result) {
            .ok => switch (task_result.target) {
                .game_detail => self.game_detail.clearBrowserErrorUrl(self.allocator.?),
                .thread => self.thread.clearBrowserErrorUrl(self.allocator.?),
            },
            .failed => |url| {
                defer self.allocator.?.free(url);
                switch (task_result.target) {
                    .game_detail => try self.game_detail.setBrowserErrorUrl(self.allocator.?, url),
                    .thread => try self.thread.setBrowserErrorUrl(self.allocator.?, url),
                }
            },
        }
    }

    fn handleResize(self: *App, size: chasen.Size) void {
        self.terminal_size = size;
        if (self.screen == .game_detail) {
            self.game_detail.setVisibleHeight(detailLayoutForTerminal(self).content_height);
        }
        if (self.screen == .thread) {
            self.thread.setVisibleHeight(threadLayoutForTerminal(self).content_height);
        }
    }

    fn drawListPosition(self: *const App, surface: *chasen.Surface, list: *const ui.List) !void {
        const item_count = list.items.len;
        if (item_count == 0 or surface.size().height < 2) return;

        const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
        _ = surface.borrowTextAt(0, list_position_row, text, self.subtleStyle());
    }

    fn drawCenteredListPosition(self: *const App, surface: *chasen.Surface, list: *const ui.List) !void {
        const item_count = list.items.len;
        if (item_count == 0 or surface.size().height < 2) return;

        const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
        ui.message_block.drawCenteredText(surface, list_position_row, text, self.subtleStyle());
    }

    fn drawSortMode(self: *const App, surface: *chasen.Surface, label: []const u8) void {
        if (surface.size().width <= 12 or surface.size().height <= list_position_row) return;
        _ = surface.borrowTextAt(10, list_position_row, label, self.subtleStyle());
    }

    fn forumThreadTitle(self: *const App) []const u8 {
        if (self.forums.selectedForum()) |forum| return forum.title;
        return "Threads";
    }

    fn drawForumThreadList(self: *const App, surface: *chasen.Surface) !void {
        const threads = self.forums.thread_page.threads;
        if (threads.len == 0 or surface.size().height == 0) return;

        // Go version renders each thread as subject + metadata, so one logical
        // item consumes two terminal rows.
        const visible_items = @max(@as(usize, 1), surface.size().height / 2);
        const range = list_view.visibleRange(threads.len, self.forums.thread_list.focusedIndex(), visible_items);
        const focused_index = self.forums.thread_list.focusedIndex();

        for (threads[range.start..range.end], 0..) |thread, local_index| {
            const global_index = range.start + local_index;
            const row: u16 = @intCast(local_index * 2);
            if (row >= surface.size().height) break;

            const focused = global_index == focused_index;
            const marker = if (focused) ">" else " ";
            _ = surface.borrowTextAt(0, row, marker, .{});
            _ = surface.borrowTextAt(2, row, thread.subject, if (focused) self.focusedStyle() else .{});

            if (row + 1 < surface.size().height) {
                const meta = try screens.forum.threadMetaText(surface.frameAllocator(), thread);
                _ = surface.borrowTextAt(4, row + 1, meta, self.subtleStyle());
            }
        }
    }

    fn drawCenteredForumList(self: *const App, surface: *chasen.Surface) !void {
        const list = &self.forums.forum_list;
        const focused_index = list.focusedIndex();
        const content_col = centeredForumListCol(surface, list.items);
        for (list.items, 0..) |item, index| {
            const row = list_body_row + @as(u16, @intCast(index));
            if (row >= surface.size().height) break;
            const marker = if (index == focused_index) "> " else "  ";
            const text = try std.fmt.allocPrint(surface.frameAllocator(), "{s}{s}", .{ marker, item });
            _ = surface.borrowTextAt(content_col, row, text, if (index == focused_index) self.focusedStyle() else .{});
        }
    }

    fn centeredForumListCol(surface: *chasen.Surface, items: []const []const u8) u16 {
        var max_width: usize = 0;
        for (items) |item| {
            max_width = @max(max_width, chasen.text.displayWidth(item) + 2);
        }
        const surface_width = surface.size().width;
        if (max_width >= surface_width) return 0;
        return @intCast((surface_width - max_width) / 2);
    }

    fn drawThreadBody(self: *const App, surface: *chasen.Surface) void {
        const range = self.thread.visibleRange(surface.size().height);
        for (self.thread.lines[range.start..range.end], 0..) |line, index| {
            const row: u16 = @intCast(index);
            if (row >= surface.size().height) break;
            const style: chasen.TextStyle = if (std.mem.startsWith(u8, line, ">") or std.mem.startsWith(u8, line, "─"))
                .{ .dim = true }
            else
                .{};
            _ = surface.borrowTextAt(0, row, line, style);
        }
    }

    fn drawManualOpenHint(self: *const App, surface: *chasen.Surface, row: u16, url: []const u8) !void {
        _ = self;
        if (row >= surface.size().height) return;
        _ = try surface.printAt(0, row, .{ .dim = true }, "Open manually: {s}", .{url});
    }

    fn drawEmptyState(self: *const App, surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8) void {
        surface.hideCursor();
        self.drawGuidance(surface, row, title, message);
    }

    fn drawGuidance(self: *const App, surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8) void {
        _ = surface.borrowTextAt(0, row, title, self.mutedTitleStyle());
        _ = surface.borrowTextAt(0, row + 1, message, self.mutedStyle());
    }

    fn drawCenteredGuidance(self: *const App, surface: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        const block = ui.MessageBlock.init(.{ .title = title, .message = message });
        block.view(surface, .{});
    }

    fn drawCenteredGuidanceKeepingCursor(self: *const App, surface: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        const block = ui.MessageBlock.init(.{ .title = title, .message = message });
        block.view(surface, .{ .hide_cursor = false });
    }

    fn drawHotFilterInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.borrowTextAt(0, list_filter_row, "Filter:", self.subtleStyle());
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
        _ = surface.borrowTextAt(0, list_filter_row, "Filter:", self.subtleStyle());
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
        _ = surface.borrowTextAt(0, 2, "User:", self.subtleStyle());
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
        _ = surface.borrowTextAt(0, list_filter_row, "Filter:", self.subtleStyle());
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

    fn drawCollectionStatusBar(self: *const App, surface: *chasen.Surface) void {
        if (surface.size().height <= collection_status_bar_row) return;
        const text = collectionStatusSummary(surface.frameAllocator(), self.collection_status_mask) catch "Status: -";
        _ = surface.borrowTextAt(0, collection_status_bar_row, text, self.subtleStyle());
    }

    fn drawCollectionStatusPicker(self: *const App, surface: *chasen.Surface, start_row: u16) void {
        if (surface.size().height <= start_row) return;

        _ = surface.borrowTextAt(0, start_row, "Status Filter", self.mutedTitleStyle());
        for (collection_status_labels, 0..) |label, index| {
            const row: u16 = @intCast(start_row + 1 + index);
            if (row >= surface.size().height) return;
            const cursor = if (self.collection_status_cursor == index) "> " else "  ";
            const checked = if ((self.collection_status_mask & collectionStatusBit(index)) != 0) "[x]" else "[ ]";
            _ = surface.borrowTextAt(0, row, cursor, .{ .bold = self.collection_status_cursor == index });
            _ = surface.borrowTextAt(2, row, checked, .{ .fg = if ((self.collection_status_mask & collectionStatusBit(index)) != 0) self.theme().accent else .gray });
            _ = surface.borrowTextAt(6, row, label, .{});
        }

        const clear_row: u16 = @intCast(start_row + 1 + collection_picker_clear_index);
        if (clear_row < surface.size().height) {
            const cursor = if (self.collection_status_cursor == collection_picker_clear_index) "> " else "  ";
            _ = surface.borrowTextAt(0, clear_row, cursor, .{ .bold = self.collection_status_cursor == collection_picker_clear_index });
            _ = surface.borrowTextAt(6, clear_row, "Show All (clear)", self.mutedStyle());
        }
    }

    fn listDensity(self: *const App) list_view.Density {
        return list_view.Density.fromConfig(self.config.interface.list_density);
    }

    fn theme(self: *const App) style_mod.Theme {
        return style_mod.Theme.fromName(self.config.interface.color_theme);
    }

    fn panelBorder(self: *const App) ui.Panel.Border {
        return style_mod.borderFromName(self.config.interface.border_style);
    }

    fn titleStyle(self: *const App) chasen.TextStyle {
        return self.theme().title;
    }

    fn focusedStyle(self: *const App) chasen.TextStyle {
        return motion.focusedStyle(self.theme().focused, self.config.interface.selection, self.animation_frame);
    }

    fn mutedStyle(self: *const App) chasen.TextStyle {
        return self.theme().muted;
    }

    fn mutedTitleStyle(self: *const App) chasen.TextStyle {
        var style = self.theme().muted;
        style.bold = true;
        return style;
    }

    fn subtleStyle(self: *const App) chasen.TextStyle {
        return self.theme().subtle;
    }

    fn requestSelectionFrameIfNeeded(self: *const App, ctx: *chasen.Ctx(Msg)) void {
        if (motion.selectionNeedsFrame(self.config.interface.selection)) {
            ctx.requestFrame();
        }
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
            .game_detail => "j/k Up/Down: scroll  o: open BGG  f: forums  b/Esc: back  m: menu  q: quit",
            .forums => switch (self.forums.mode) {
                .forum_list => "Up/Down: move  Enter: threads  b: detail  Esc/m: menu  q: quit",
                .thread_list => "Up/Down: move  Enter: read  n/p: page  b: forums  Esc/m: menu  q: quit",
            },
            .thread => "j/k Up/Down: scroll  s: sort  o: open BGG  b: back  Esc/m: menu  q: quit",
            .collection => switch (self.collection.load_state) {
                .idle, .failed => "Enter: load  Esc: menu",
                .loading => "Esc: menu",
                .loaded => if (self.collection_status_picker)
                    "Up/Down: move  Enter: toggle  Esc: close"
                else if (self.collection.filter_active)
                    "Type: filter  Up/Down: move  Enter: detail  Esc: clear"
                else
                    "Up/Down: move  Enter: detail  /: filter  s: status  r: refresh  u: user  Esc/m: menu  q: quit",
            },
            .settings => if (self.settings.editing != null)
                "Enter: save  Esc: cancel"
            else if (self.settings.focusedEditField()) |field|
                switch (field) {
                    .token => "Up/Down: move  Enter: edit token  m: menu  Esc/q: quit",
                    .username => "Up/Down: move  Enter: edit username  m: menu  Esc/q: quit",
                    .list_width => "Up/Down: move  Enter: edit list width  m: menu  Esc/q: quit",
                    .thread_width => "Up/Down: move  Enter: edit thread width  m: menu  Esc/q: quit",
                    .detail_width => "Up/Down: move  Enter: edit detail width  m: menu  Esc/q: quit",
                }
            else if (self.settings.focusedCycleField() != null)
                "Up/Down: move  Enter: change setting  m: menu  Esc/q: quit"
            else
                "Up/Down: move  m: menu  Esc/q: quit",
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
        self.labels = try labels_mod.buildHotGameLabels(allocator, games);
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
        labels_mod.freeHotGameLabels(allocator, self.labels);
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
        self.labels = try labels_mod.buildSearchResultLabels(allocator, results);
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
        labels_mod.freeSearchResultLabels(allocator, self.labels);
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
    // Keep the API result intact so status toggles can filter locally without another request.
    all_items: []bgg_model.CollectionItem = &.{},
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

    fn setLoaded(self: *CollectionState, allocator: std.mem.Allocator, items: []bgg_model.CollectionItem, status_mask: u8) !void {
        self.clearItems(allocator);
        self.all_items = items;
        try self.applyStatusFilter(allocator, status_mask);
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

    fn statusFilteredEmpty(self: *const CollectionState) bool {
        return self.all_items.len > 0 and self.items.len == 0;
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

    fn applyStatusFilter(self: *CollectionState, allocator: std.mem.Allocator, status_mask: u8) !void {
        var projected: std.ArrayList(bgg_model.CollectionItem) = .empty;
        errdefer projected.deinit(allocator);

        for (self.all_items) |item| {
            if (!collectionItemMatchesStatusMask(item, status_mask)) continue;
            try projected.append(allocator, item);
        }

        const next_items = try projected.toOwnedSlice(allocator);
        errdefer allocator.free(next_items);
        const next_labels = try labels_mod.buildCollectionItemLabels(allocator, next_items);
        errdefer labels_mod.freeCollectionItemLabels(allocator, next_labels);

        self.filter.deinit(allocator);
        labels_mod.freeCollectionItemLabels(allocator, self.labels);
        allocator.free(self.items);
        self.items = next_items;
        self.labels = next_labels;
        self.list = ui.List.init(.{ .items = self.labels });
        self.filter_active = false;
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
        labels_mod.freeCollectionItemLabels(allocator, self.labels);
        allocator.free(self.items);
        bgg_xml.freeCollectionItems(allocator, self.all_items);
        self.labels = &.{};
        self.all_items = &.{};
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

const GameDetailResult = union(enum) {
    ok: []bgg_model.Game,
    failed: []const u8,
};

const GameDetailTaskResult = struct {
    request_id: u64,
    result: GameDetailResult,
};

const ForumListResult = union(enum) {
    ok: []bgg_model.Forum,
    failed: []const u8,
};

const ForumListTaskResult = struct {
    request_id: u64,
    result: ForumListResult,
};

const ForumThreadsResult = union(enum) {
    ok: bgg_model.ThreadList,
    failed: []const u8,
};

const ForumThreadsTaskResult = struct {
    request_id: u64,
    result: ForumThreadsResult,
};

const ThreadResult = union(enum) {
    ok: bgg_model.Thread,
    failed: []const u8,
};

const ThreadTaskResult = struct {
    request_id: u64,
    result: ThreadResult,
};

const BrowserOpenResult = union(enum) {
    ok,
    failed: []u8,
};

const BrowserTarget = enum {
    game_detail,
    thread,
};

const BrowserOpenTaskResult = struct {
    request_id: u64,
    target: BrowserTarget,
    result: BrowserOpenResult,
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
            .result = loadCollectionItems(allocator, io, task.token, task.username) catch |err| .{ .failed = @errorName(err) },
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

const ForumListTask = struct {
    token: []const u8,
    game_id: u32,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *ForumListTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.destroy(task);
        }

        return .{ .forums_loaded = .{
            .request_id = task.request_id,
            .result = loadForumList(allocator, io, task.token, task.game_id) catch |err| .{ .failed = @errorName(err) },
        } };
    }
};

const ForumThreadsTask = struct {
    token: []const u8,
    forum_id: u32,
    page: u32,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *ForumThreadsTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.destroy(task);
        }

        return .{ .forum_threads_loaded = .{
            .request_id = task.request_id,
            .result = loadForumThreads(allocator, io, task.token, task.forum_id, task.page) catch |err| .{ .failed = @errorName(err) },
        } };
    }
};

const ThreadTask = struct {
    token: []const u8,
    thread_id: u32,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *ThreadTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.destroy(task);
        }

        return .{ .thread_loaded = .{
            .request_id = task.request_id,
            .result = loadThread(allocator, io, task.token, task.thread_id) catch |err| .{ .failed = @errorName(err) },
        } };
    }
};

const BrowserOpenTask = struct {
    url: []u8,
    request_id: u64,
    target: BrowserTarget,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *BrowserOpenTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.destroy(task);
        }

        browser.openUrl(io, task.url) catch {
            return .{ .browser_opened = .{
                .request_id = task.request_id,
                .target = task.target,
                .result = .{ .failed = task.url },
            } };
        };
        allocator.free(task.url);
        return .{ .browser_opened = .{
            .request_id = task.request_id,
            .target = task.target,
            .result = .ok,
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

fn loadForumList(allocator: std.mem.Allocator, io: std.Io, token: []const u8, game_id: u32) !ForumListResult {
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

fn loadForumThreads(allocator: std.mem.Allocator, io: std.Io, token: []const u8, forum_id: u32, page: u32) !ForumThreadsResult {
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

fn loadThread(allocator: std.mem.Allocator, io: std.Io, token: []const u8, thread_id: u32) !ThreadResult {
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

fn drawDescriptionPreview(surface: *chasen.Surface, description: []const u8) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    _ = surface.borrowTextAt(0, 0, "Description", .{ .bold = true });
    if (description.len == 0) {
        _ = surface.borrowTextAt(0, 2, "-", .{ .fg = .gray });
        return;
    }

    var row: u16 = 2;
    var line_start: usize = 0;
    var index: usize = 0;
    while (index <= description.len and row < size.height) : (index += 1) {
        if (index == description.len or description[index] == '\n') {
            const line = std.mem.trim(u8, description[line_start..index], " \t\r");
            if (line.len > 0) {
                _ = surface.borrowTextAt(0, row, line, .{});
                row += 1;
            }
            line_start = index + 1;
        }
    }
}

fn drawListLine(surface: *chasen.Surface, row: u16, label: []const u8, values: []const []const u8) !void {
    if (row >= surface.size().height) return;
    const text = try listLineText(surface.frameAllocator(), label, values);
    _ = surface.borrowTextAt(0, row, text, .{ .fg = .gray });
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

fn formatOwnedText(allocator: std.mem.Allocator, write_fn: anytype, args: anytype) ![]u8 {
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

fn collectionStatusBit(index: usize) u8 {
    return @as(u8, 1) << @intCast(index);
}

fn collectionItemMatchesStatusMask(item: bgg_model.CollectionItem, status_mask: u8) bool {
    if (status_mask == 0) return true;
    return ((status_mask & collectionStatusBit(0)) != 0 and item.owned) or
        ((status_mask & collectionStatusBit(1)) != 0 and item.prev_owned) or
        ((status_mask & collectionStatusBit(2)) != 0 and item.for_trade) or
        ((status_mask & collectionStatusBit(3)) != 0 and item.want) or
        ((status_mask & collectionStatusBit(4)) != 0 and item.want_to_play) or
        ((status_mask & collectionStatusBit(5)) != 0 and item.want_to_buy) or
        ((status_mask & collectionStatusBit(6)) != 0 and item.wishlist) or
        ((status_mask & collectionStatusBit(7)) != 0 and item.preordered);
}

fn collectionStatusSummary(allocator: std.mem.Allocator, status_mask: u8) ![]const u8 {
    if (status_mask == 0) return try allocator.dupe(u8, "Status: All");

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("Status: ");
    var wrote = false;
    for (collection_status_labels, 0..) |label, index| {
        if ((status_mask & collectionStatusBit(index)) == 0) continue;
        if (wrote) try out.writer.writeAll(", ");
        try out.writer.writeAll(label);
        wrote = true;
    }
    return try out.toOwnedSlice();
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

fn mainMenuContentWidth() u16 {
    var width: usize = 0;
    for (menu_items) |item| {
        width = @max(width, 2 + chasen.text.displayWidth(item.label));
        if (item.shortcut) |shortcut| {
            width = @max(width, @as(usize, main_menu_shortcut_col) + chasen.text.displayWidth(shortcut));
        }
    }
    return @intCast(@min(width, std.math.maxInt(u16)));
}

fn detailSurface(surface: *chasen.Surface, configured_width: u16) chasen.Surface {
    // Detail is long-form content, so it uses the available body height while
    // still constraining width through the user's display setting.
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = configured_width,
        .height = surface.size().height,
    }));
}

fn constrainedListSurface(surface: *chasen.Surface) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), list_screen_max_size));
}

fn forumSurface(surface: *chasen.Surface) chasen.Surface {
    return surface.child(ui.layout.center(surfaceRect(surface), forum_screen_max_size));
}

fn forumListSurface(surface: *chasen.Surface, item_count: usize) chasen.Surface {
    const count: u16 = @intCast(@min(item_count, std.math.maxInt(u16)));
    const height = @min(forum_screen_max_size.height, @max(@as(u16, 7), list_body_row + count + 2));
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = forum_screen_max_size.width,
        .height = height,
    }));
}

fn threadSurface(surface: *chasen.Surface, configured_width: u16) chasen.Surface {
    // Threads are long-form content like Detail, so height follows the available
    // body while width remains user-configurable.
    return surface.child(ui.layout.center(surfaceRect(surface), .{
        .width = configured_width,
        .height = surface.size().height,
    }));
}

fn threadLayout(area_height: u16, density: []const u8) screens.thread.Layout {
    return screens.thread.layout(area_height, density, .{ .outer_reserved_rows = thread_outer_reserved_rows });
}

fn threadLayoutForTerminal(self: *const App) screens.thread.Layout {
    return threadLayout(screenBodySizeForTerminal(self.terminal_size).height, self.config.interface.list_density);
}

fn detailLayout(area_height: u16, density: []const u8) screens.detail.Layout {
    // The Go version computed detail density from full terminal height. Chasen
    // renders inside a panel plus global status row, so compensate for that
    // outer chrome while keeping Detail's child surface as the drawing boundary.
    return screens.detail.layout(area_height, density, .{ .outer_reserved_rows = detail_outer_reserved_rows });
}

fn detailLayoutForTerminal(self: *const App) screens.detail.Layout {
    return detailLayout(screenBodySizeForTerminal(self.terminal_size).height, self.config.interface.list_density);
}

fn screenBodySizeForTerminal(terminal_size: chasen.Size) chasen.Size {
    const shell_rect = chasen.Rect{
        .col = 0,
        .row = 0,
        .width = terminal_size.width,
        .height = terminal_size.height -| 1,
    };
    const body_rect = ui.Panel.contentRectFor(shell_rect, .all(1));
    return .{
        .width = body_rect.width,
        .height = @max(@as(u16, 1), body_rect.height),
    };
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
        .forums => "forums",
        .thread => "thread",
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

fn inputWidthValue(input: anytype, config: config_mod.Config, field: screens.settings.EditField) !void {
    const value: u16 = switch (field) {
        .list_width => config.display.list_width,
        .thread_width => config.display.thread_width,
        .detail_width => config.display.detail_width,
        else => return,
    };
    var buf: [8]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{d}", .{value});
    try insertPastedCodepoints(input, text);
}

fn parseSettingsWidth(text: []const u8) !u16 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const value = try std.fmt.parseInt(u16, trimmed, 10);
    if (value < 20 or value > 240) return error.InvalidWidth;
    return value;
}

const color_theme_values = [_][]const u8{ "default", "blue", "orange", "mono", "matcha" };
const transition_values = [_][]const u8{ "none", "fade", "glitch", "dissolve", "sweep", "lines", "lines-cross", "random" };
const selection_values = [_][]const u8{ "none", "wave", "blink", "glitch" };
const border_style_values = [_][]const u8{ "none", "rounded", "thick", "double", "block", "dots" };
const list_density_values = [_][]const u8{ "compact", "normal", "comfortable", "relaxed" };
const date_format_values = [_][]const u8{ "yyyy-mm-dd", "yyyy/mm/dd", "relative", "YYYY-MM-DD" };

fn nextCycleValue(current: []const u8, values: []const []const u8) []const u8 {
    for (values, 0..) |value, index| {
        if (std.mem.eql(u8, current, value)) {
            return values[(index + 1) % values.len];
        }
    }
    return values[0];
}

fn nextImageProtocol(current: config_mod.ImageProtocol) config_mod.ImageProtocol {
    return switch (current) {
        .auto => .kitty,
        .kitty => .off,
        .off => .auto,
    };
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

test "screen body size follows shell panel content rect" {
    const body_size = screenBodySizeForTerminal(.{ .width = 80, .height = 10 });

    try std.testing.expectEqual(@as(u16, 76), body_size.width);
    try std.testing.expectEqual(@as(u16, 5), body_size.height);
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
    try std.testing.expectEqualStrings("forums", screenTitle(.forums));
    try std.testing.expectEqualStrings("thread", screenTitle(.thread));
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
    try std.testing.expectEqualStrings("j/k Up/Down: scroll  o: open BGG  f: forums  b/Esc: back  m: menu  q: quit", app.footerHint());

    app.screen = .forums;
    app.forums.mode = .forum_list;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: threads  b: detail  Esc/m: menu  q: quit", app.footerHint());
    app.forums.mode = .thread_list;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: read  n/p: page  b: forums  Esc/m: menu  q: quit", app.footerHint());

    app.screen = .thread;
    try std.testing.expectEqualStrings("j/k Up/Down: scroll  s: sort  o: open BGG  b: back  Esc/m: menu  q: quit", app.footerHint());

    app.screen = .collection;
    try std.testing.expectEqualStrings("Enter: load  Esc: menu", app.footerHint());
    app.collection.load_state = .loading;
    try std.testing.expectEqualStrings("Esc: menu", app.footerHint());
    app.collection.load_state = .loaded;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: detail  /: filter  s: status  r: refresh  u: user  Esc/m: menu  q: quit", app.footerHint());
    app.collection_status_picker = true;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: toggle  Esc: close", app.footerHint());
    app.collection_status_picker = false;
    app.collection.filter_active = true;
    try std.testing.expectEqualStrings("Type: filter  Up/Down: move  Enter: detail  Esc: clear", app.footerHint());
    app.collection.filter_active = false;

    app.screen = .settings;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: change setting  m: menu  Esc/q: quit", app.footerHint());
    for (0..8) |_| app.settings.updateList(.move_next);
    try std.testing.expectEqualStrings("Up/Down: move  Enter: edit list width  m: menu  Esc/q: quit", app.footerHint());
    app.settings.updateList(.move_next);
    try std.testing.expectEqualStrings("Up/Down: move  Enter: edit thread width  m: menu  Esc/q: quit", app.footerHint());
    app.settings.updateList(.move_next);
    try std.testing.expectEqualStrings("Up/Down: move  Enter: edit detail width  m: menu  Esc/q: quit", app.footerHint());
    app.settings.updateList(.move_next);
    try std.testing.expectEqualStrings("Up/Down: move  Enter: edit username  m: menu  Esc/q: quit", app.footerHint());
    app.settings.updateList(.move_next);
    try std.testing.expectEqualStrings("Up/Down: move  Enter: edit token  m: menu  Esc/q: quit", app.footerHint());
    app.settings.startEdit(.token);
    try std.testing.expectEqualStrings("Enter: save  Esc: cancel", app.footerHint());
    app.settings.stopEditing();
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

test "collection status filter initializes from config" {
    const app = App.create(.{
        .api = .{ .token = "token" },
        .collection = .{ .status_filter = .{ .mask = collectionStatusBit(6) } },
    }, .{});

    try std.testing.expectEqual(collectionStatusBit(6), app.collection_status_mask);
}

test "collection status mask filters matching items" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items, collectionStatusBit(0) | collectionStatusBit(6));
    defer state.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), state.items.len);
    try state.applyStatusFilter(std.testing.allocator, collectionStatusBit(6));
    try std.testing.expectEqual(@as(usize, 2), state.items.len);
    try std.testing.expectEqual(@as(u32, 2), state.items[0].id);
    try std.testing.expectEqual(@as(u32, 3), state.items[1].id);
    try state.applyStatusFilter(std.testing.allocator, 0);
    try std.testing.expectEqual(@as(usize, 3), state.items.len);
}

test "collection status filter distinguishes filtered empty from API empty" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items, collectionStatusBit(6));
    defer state.deinit(std.testing.allocator);

    try std.testing.expect(state.statusFilteredEmpty());
    try state.applyStatusFilter(std.testing.allocator, 0);
    try std.testing.expect(!state.statusFilteredEmpty());
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

    try app.collection.setLoaded(std.testing.allocator, items, 0);

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
    try app.collection.setLoaded(std.testing.allocator, items, 0);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = '/' } }).?;
    try std.testing.expect(msg == .collection_filter_start);
}

test "loaded collection handles change user and refresh shortcuts" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };
    try app.collection.setLoaded(std.testing.allocator, items, 0);

    const user_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'u' } }).?;
    try std.testing.expect(user_msg == .collection_change_user);

    const refresh_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'r' } }).?;
    try std.testing.expect(refresh_msg == .collection_refresh);
}

test "loaded collection s opens status picker" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };
    try app.collection.setLoaded(std.testing.allocator, items, 0);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = 's' } }).?;
    try std.testing.expect(msg == .collection_status_open);
}

test "collection status picker toggles multiple statuses without request" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };
    app.collection_status_mask = collectionStatusBit(0);
    try app.collection.setLoaded(std.testing.allocator, items, collectionStatusBit(0));

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.openCollectionStatusPicker();
    app.collection_status_cursor = 6;
    try app.toggleCollectionStatus(&tc.ctx);

    try std.testing.expectEqual(collectionStatusBit(0) | collectionStatusBit(6), app.collection_status_mask);
    try std.testing.expectEqual(collectionStatusBit(0) | collectionStatusBit(6), app.config.collection.status_filter.mask);
    try std.testing.expectEqual(@as(usize, 3), app.collection.items.len);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);

    app.collection_status_cursor = collection_picker_clear_index;
    try app.toggleCollectionStatus(&tc.ctx);

    try std.testing.expectEqual(@as(u8, 0), app.collection_status_mask);
    try std.testing.expectEqual(@as(u8, 0), app.config.collection.status_filter.mask);
    try std.testing.expectEqual(@as(usize, 3), app.collection.items.len);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "changing collection user clears loaded state and invalidates tasks" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.collection_filter_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "ca" });
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };
    try app.collection.setLoaded(std.testing.allocator, items, 0);
    try app.collection.applyFilter(std.testing.allocator, "cat");
    app.collection_request_id = 7;

    try app.changeCollectionUser();

    try std.testing.expect(app.collection.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.collection.items.len);
    try std.testing.expect(!app.collection.filter_active);
    try std.testing.expectEqualStrings("", app.collection_filter_input.?.text());
    try std.testing.expectEqual(@as(u64, 8), app.collection_request_id);
}

test "collection filter maps visible activation back to source item" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items, 0);
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(usize, 2), state.sourceIndex(state.activeList().focusedIndex()).?);
}

test "collection status and name filters activate projected item" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "CATAN"), .wishlist = true };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items, collectionStatusBit(6));
    defer state.deinit(std.testing.allocator);

    try state.applyFilter(std.testing.allocator, "ca");
    state.update(.move_next);

    const projected_index = state.sourceIndex(state.activeList().focusedIndex()).?;
    try std.testing.expectEqual(@as(u32, 3), state.items[projected_index].id);
}

test "collection focus resets and clamps after status projection" {
    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };

    var state: CollectionState = .{};
    try state.setLoaded(std.testing.allocator, items, collectionStatusBit(6));
    defer state.deinit(std.testing.allocator);

    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());

    try state.applyStatusFilter(std.testing.allocator, collectionStatusBit(0));
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    try std.testing.expectEqual(@as(u32, 1), state.items[state.sourceIndex(0).?].id);
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

test "loaded game detail f opens forums" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "Catan") };
    try app.game_detail.setLoaded(std.testing.allocator, games, 90);
    app.screen = .game_detail;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'f' } }).?;
    try std.testing.expect(msg == .forum_open);
}

test "loaded game detail o opens browser" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "Catan") };
    try app.game_detail.setLoaded(std.testing.allocator, games, 90);
    app.screen = .game_detail;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'o' } }).?;
    try std.testing.expect(msg == .game_detail_open_browser);
}

test "forum back key returns to detail or forum list" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.screen = .forums;
    app.forums.mode = .forum_list;
    const detail_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'b' } }).?;
    try std.testing.expect(detail_msg == .forum_back_to_detail);

    app.forums.mode = .thread_list;
    const list_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'b' } }).?;
    try std.testing.expect(list_msg == .forum_back_to_list);
}

test "forum back to list invalidates in-flight thread load" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.thread_list_request_id = 7;
    app.forums.mode = .thread_list;
    app.backToForumList();
    try std.testing.expectEqual(@as(u64, 8), app.thread_list_request_id);
    try std.testing.expectEqual(screens.forum.Mode.forum_list, app.forums.mode);

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Old response"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };
    try app.finishForumThreads(.{
        .request_id = 7,
        .result = .{ .ok = .{ .threads = threads, .page = 1, .total_pages = 1 } },
    });

    try std.testing.expectEqual(screens.forum.Mode.forum_list, app.forums.mode);
    try std.testing.expect(app.forums.thread_page.threads.len == 0);
}

test "thread scroll uses resized body height" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.screen = .thread;
    app.handleResize(.{ .width = 80, .height = 10 });
    try std.testing.expectEqual(threadLayoutForTerminal(&app).content_height, app.thread.visible_height);

    const text = try std.testing.allocator.dupe(u8, "0\n1\n2\n3\n4\n5\n6\n7\n8\n9");
    app.thread.rendered_text = text;
    const lines = try std.testing.allocator.alloc([]const u8, 10);
    for (lines, 0..) |*line, index| {
        line.* = text[index * 2 .. index * 2 + 1];
    }
    app.thread.lines = lines;
    app.thread.load_state = .loaded;

    for (0..10) |_| app.thread.moveDown(threadLayoutForTerminal(&app).content_height);
    try std.testing.expectEqual(app.thread.maxScroll(threadLayoutForTerminal(&app).content_height), app.thread.scroll);
}

test "detail scroll uses resized body height" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.screen = .game_detail;
    app.handleResize(.{ .width = 80, .height = 10 });
    try std.testing.expectEqual(detailLayoutForTerminal(&app).content_height, app.game_detail.visible_height);

    const text = try std.testing.allocator.dupe(u8, "0\n1\n2\n3\n4\n5\n6\n7\n8\n9");
    app.game_detail.rendered_text = text;
    const lines = try std.testing.allocator.alloc([]const u8, 10);
    for (lines, 0..) |*line, index| {
        line.* = text[index * 2 .. index * 2 + 1];
    }
    app.game_detail.lines = lines;
    app.game_detail.load_state = .loaded;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    for (0..10) |_| try app.update(.game_detail_move_next, &tc.ctx);
    try std.testing.expectEqual(app.game_detail.maxScroll(detailLayoutForTerminal(&app).content_height), app.game_detail.scroll);
}

test "loaded thread o opens browser" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .thread;
    app.thread.thread_id = 100;
    app.thread.load_state = .loaded;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'o' } }).?;
    try std.testing.expect(msg == .thread_open_browser);
}

test "stale browser failure does not update current thread" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.browser_request_id = 2;
    try app.finishBrowserOpen(.{
        .request_id = 1,
        .target = .thread,
        .result = .{ .failed = try std.testing.allocator.dupe(u8, "https://boardgamegeek.com/thread/1") },
    });

    try std.testing.expectEqualStrings("", app.thread.browser_error_url);
}

test "opening another thread invalidates in-flight browser result" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 2,
        .subject = try std.testing.allocator.dupe(u8, "Next thread"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };
    try app.forums.setThreadsLoaded(std.testing.allocator, .{
        .threads = threads,
        .page = 1,
        .total_pages = 1,
    });

    app.browser_request_id = 7;
    const next_thread = app.forums.thread_page.threads[0];
    app.thread_request_id +%= 1;
    app.browser_request_id +%= 1;
    app.thread.startLoad(std.testing.allocator, next_thread.id, app.config.display.thread_width);
    app.screen = .thread;
    try std.testing.expectEqual(@as(u64, 8), app.browser_request_id);

    try app.finishBrowserOpen(.{
        .request_id = 7,
        .target = .thread,
        .result = .{ .failed = try std.testing.allocator.dupe(u8, "https://boardgamegeek.com/thread/1") },
    });
    try std.testing.expectEqualStrings("", app.thread.browser_error_url);
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

test "settings token edit saves token and stays on settings" {
    var app = App.create(.{ .api = .{ .token = "old-token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .settings;
    app.settings_token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "  new-token  " });
    app.settings.startEdit(.token);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsToken(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("new-token", app.config.apiClientToken().?);
    try std.testing.expectEqualStrings("", app.settings_token_input.?.text());
}

test "settings token edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-token/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings_token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "settings-token" });
    app.settings.startEdit(.token);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.submitSettingsToken(&tc.ctx);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("settings-token", loaded.config.apiClientToken().?);
}

test "settings token edit cancel clears input without changing token" {
    var app = App.create(.{ .api = .{ .token = "old-token" } }, .{});
    app.allocator = std.testing.allocator;
    app.settings_token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "new-token" });
    app.settings.startEdit(.token);
    defer app.deinitOwnedState();

    app.cancelSettingsTokenEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("old-token", app.config.apiClientToken().?);
    try std.testing.expectEqualStrings("", app.settings_token_input.?.text());
}

test "settings username edit saves username and stays on settings" {
    var app = App.create(.{ .collection = .{ .default_username = "old-user" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .settings;
    app.settings_username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "  new-user  " });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsUsername(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("new-user", app.config.collection.default_username.?);
    try std.testing.expectEqualStrings("", app.settings_username_input.?.text());
}

test "settings username edit clears username when empty" {
    var app = App.create(.{ .collection = .{ .default_username = "old-user" } }, .{});
    app.allocator = std.testing.allocator;
    app.settings_username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "   " });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsUsername(&tc.ctx);

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expect(app.config.collection.default_username == null);
    try std.testing.expectEqualStrings("", app.settings_username_input.?.text());
}

test "settings username edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-username/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings_username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "hiro" });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.submitSettingsUsername(&tc.ctx);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hiro", loaded.config.collection.default_username.?);
}

test "settings username edit cancel clears input without changing username" {
    var app = App.create(.{ .collection = .{ .default_username = "old-user" } }, .{});
    app.allocator = std.testing.allocator;
    app.settings_username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "new-user" });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    app.cancelSettingsUsernameEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("old-user", app.config.collection.default_username.?);
    try std.testing.expectEqualStrings("", app.settings_username_input.?.text());
}

test "settings width edit saves selected width and stays on settings" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    app.screen = .settings;
    app.settings_width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "120" });
    app.settings.startEdit(.thread_width);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsWidth(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqual(@as(u16, 120), app.config.display.thread_width);
    try std.testing.expectEqualStrings("", app.settings_width_input.?.text());
}

test "settings width edit ignores invalid width" {
    var app = App.create(.{ .display = .{ .list_width = 40 } }, .{});
    app.allocator = std.testing.allocator;
    app.settings_width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "10" });
    app.settings.startEdit(.list_width);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsWidth(&tc.ctx);

    try std.testing.expectEqual(@as(u16, 40), app.config.display.list_width);
    try std.testing.expectEqual(screens.settings.EditField.list_width, app.settings.editing.?);
    try std.testing.expectEqualStrings("10", app.settings_width_input.?.text());
}

test "settings width edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-width/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings_width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "144" });
    app.settings.startEdit(.detail_width);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.submitSettingsWidth(&tc.ctx);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 144), loaded.config.display.detail_width);
}

test "settings width edit cancel clears input without changing width" {
    var app = App.create(.{ .display = .{ .detail_width = 90 } }, .{});
    app.allocator = std.testing.allocator;
    app.settings_width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "120" });
    app.settings.startEdit(.detail_width);
    defer app.deinitOwnedState();

    app.cancelSettingsWidthEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqual(@as(u16, 90), app.config.display.detail_width);
    try std.testing.expectEqualStrings("", app.settings_width_input.?.text());
}

test "settings show images toggle flips display config" {
    var app = App.create(.{ .display = .{ .show_images = true } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.toggleSettingsShowImages(&tc.ctx);

    try std.testing.expect(!app.config.display.show_images);
}

test "settings show images toggle saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-show-images/config.toml";

    var app = App.create(.{ .display = .{ .show_images = true } }, .{ .config_path = path });

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.toggleSettingsShowImages(&tc.ctx);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expect(!loaded.config.display.show_images);
}

test "settings image protocol cycles through supported values" {
    var app = App.create(.{ .display = .{ .image_protocol = .auto } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.cycleSettingsField(&tc.ctx, .image_protocol);
    try std.testing.expectEqual(config_mod.ImageProtocol.kitty, app.config.display.image_protocol);

    try app.cycleSettingsField(&tc.ctx, .image_protocol);
    try std.testing.expectEqual(config_mod.ImageProtocol.off, app.config.display.image_protocol);

    try app.cycleSettingsField(&tc.ctx, .image_protocol);
    try std.testing.expectEqual(config_mod.ImageProtocol.auto, app.config.display.image_protocol);
}

test "settings image protocol cycle saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-image-protocol/config.toml";

    var app = App.create(.{ .display = .{ .image_protocol = .auto } }, .{ .config_path = path });

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.cycleSettingsField(&tc.ctx, .image_protocol);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(config_mod.ImageProtocol.kitty, loaded.config.display.image_protocol);
}

test "settings interface cycle fields update supported values" {
    var app = App.create(.{}, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.cycleSettingsField(&tc.ctx, .color_theme);
    try std.testing.expectEqualStrings("blue", app.config.interface.color_theme);
    try app.cycleSettingsField(&tc.ctx, .transition);
    try std.testing.expectEqualStrings("fade", app.config.interface.transition);
    try app.cycleSettingsField(&tc.ctx, .selection);
    try std.testing.expectEqualStrings("wave", app.config.interface.selection);
    try app.cycleSettingsField(&tc.ctx, .border_style);
    try std.testing.expectEqualStrings("thick", app.config.interface.border_style);
    try app.cycleSettingsField(&tc.ctx, .list_density);
    try std.testing.expectEqualStrings("comfortable", app.config.interface.list_density);
    try app.cycleSettingsField(&tc.ctx, .date_format);
    try std.testing.expectEqualStrings("yyyy/mm/dd", app.config.interface.date_format);
}

test "blink selection requests animation frames" {
    var app = App.create(.{ .interface = .{ .selection = "blink" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try std.testing.expect(tc.ctx.frame_requested);

    tc.resetTransient();
    try app.update(.{ .frame = .{ .now_ns = 100, .delta_ns = 16, .index = 15 } }, &tc.ctx);
    try std.testing.expectEqual(@as(u64, 15), app.animation_frame);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "non-blink selection does not request animation frames" {
    var app = App.create(.{}, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try std.testing.expect(!tc.ctx.frame_requested);
}

test "settings interface cycle wraps unknown values to first supported value" {
    var app = App.create(.{ .interface = .{ .color_theme = "custom" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.cycleSettingsField(&tc.ctx, .color_theme);

    try std.testing.expectEqualStrings("default", app.config.interface.color_theme);
}

test "settings interface cycle saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-interface-cycle/config.toml";

    var app = App.create(.{}, .{ .config_path = path });

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.cycleSettingsField(&tc.ctx, .list_density);

    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var loaded = try config_mod.loadConfig(std.testing.allocator, std.testing.io, path, &env);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("comfortable", loaded.config.interface.list_density);
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

test "hot games focus clamps in source and sorted projections" {
    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 2);
    games[0] = .{ .id = 1, .rank = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    games[1] = .{ .id = 2, .rank = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: HotGamesState = .{};
    try state.setLoaded(std.testing.allocator, games);
    defer state.deinit(std.testing.allocator);

    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());

    try state.toggleSort(std.testing.allocator);
    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
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

test "search results focus clamps in source and sorted projections" {
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 2);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    results[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Cascadia") };

    var state: SearchState = .{};
    try state.setLoaded(std.testing.allocator, results);
    defer state.deinit(std.testing.allocator);

    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());

    try state.toggleSort(std.testing.allocator);
    state.update(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.activeList().focusedIndex());
    state.update(.move_next);
    state.update(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.activeList().focusedIndex());
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

test "centered surface shrinks for narrow terminals" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(36, 10);
    defer ts.deinit();

    const area = centeredSurface(&ts.surface, .{ .width = 72, .height = 27 });

    try std.testing.expectEqual(@as(u16, 36), area.size().width);
    try std.testing.expectEqual(@as(u16, 10), area.size().height);
}

test "detail surface clamps configured width to available width" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(50, 16);
    defer ts.deinit();

    const area = detailSurface(&ts.surface, 120);

    try std.testing.expectEqual(@as(u16, 50), area.size().width);
    try std.testing.expectEqual(@as(u16, 16), area.size().height);
}
