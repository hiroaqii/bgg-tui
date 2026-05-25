const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");
const ui = @import("chasen_ui");

const bgg_model = @import("bgg/model.zig");
const bgg_xml = @import("bgg/xml.zig");
const browser = @import("browser.zig");
const config_mod = @import("config.zig");
const features = @import("features/root.zig");
const format = @import("format.zig");
const image_mod = @import("image.zig");
const labels_mod = @import("labels.zig");
const layout_mod = @import("layout.zig");
const list_filter = @import("list_filter.zig");
const list_sort = @import("list_sort.zig");
const list_view = @import("list_view.zig");
const motion = @import("motion.zig");
const paste = @import("paste.zig");
const screens = @import("screens/root.zig");
const style_mod = @import("style.zig");
const task_bgg = @import("tasks/bgg.zig");
const transitions = @import("transitions.zig");

// Keep top-level screens centered until a screen needs its own full-page layout.
const main_menu_size = chasen.Size{ .width = 48, .height = 12 };
const setup_token_size = chasen.Size{ .width = 56, .height = 9 };
const placeholder_size = chasen.Size{ .width = 56, .height = 6 };
const search_input_size = chasen.Size{ .width = 56, .height = 9 };
const collection_input_size = chasen.Size{ .width = 56, .height = 9 };
const forum_screen_max_size = layout_mod.forum_screen_max_size;
const detail_image_panel_gap = layout_mod.detail_image_panel_gap;
const list_image_panel_gap = layout_mod.list_image_panel_gap;
const list_image_focus_settle_frames = features.list_image.focus_settle_frames;

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

const NavigationState = struct {
    detail_back_screen: Screen = .main_menu,
};

const BrowserState = struct {
    request_id: u64 = 0,
};

const ListImageSource = features.list_image.Source;
const ListImageState = features.list_image.State;
const ListSortMode = list_sort.Mode;

pub const App = struct {
    config: config_mod.Config,
    config_path: ?[]const u8 = null,
    image_cache_dir: ?[]const u8 = null,
    screen: Screen,
    allocator: ?std.mem.Allocator = null,
    setup_token_input: ?ui.PasswordInput = null,
    owned_token: ?[]u8 = null,
    owned_default_username: ?[]u8 = null,
    hot_games: HotGamesState = .{},
    search: SearchState = .{},
    collection: CollectionState = .{},
    game_detail: screens.detail.State = .{},
    forums: screens.forum.State = .{},
    thread: screens.thread.State = .{},
    navigation: NavigationState = .{},
    browser: BrowserState = .{},
    list_image: ListImageState = .{},
    settings: screens.settings.State = .{},
    terminal_size: chasen.Size = forum_screen_max_size,
    menu: ui.Menu = ui.Menu.init(.{ .items = &menu_items }),
    animation_frame: u64 = 0,
    loading_scan_start_frame: u64 = 0,
    transition_choice_seed: u64 = 0,
    screen_transition: anim.Transition = .{},
    transition_from_screen: ?Screen = null,
    transition_to_screen: ?Screen = null,
    pub const Msg = union(enum) {
        setup_token: SetupTokenMsg,
        hot_games: HotGamesMsg,
        search: SearchMsg,
        collection: CollectionMsg,
        game_detail: GameDetailMsg,
        list_image: ListImageMsg,
        forum: ForumMsg,
        thread: ThreadMsg,
        browser: BrowserMsg,
        settings: screens.settings.Msg,
        terminal_resized: chasen.Size,
        frame: chasen.Frame,
        menu: ui.Menu.Msg,
        show_screen: Screen,
        quit,
    };

    pub const Options = struct {
        config_path: ?[]const u8 = null,
        image_cache_dir: ?[]const u8 = null,
    };

    pub fn create(config: config_mod.Config, options: Options) App {
        return .{
            .config = config,
            .config_path = options.config_path,
            .image_cache_dir = options.image_cache_dir,
            .screen = if (config.apiClientToken() == null) .setup_token else .main_menu,
            .collection = .{ .status_mask = config.collection.status_filter.mask },
        };
    }

    pub fn init(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.allocator = ctx.allocator();
        self.setup_token_input = try ui.PasswordInput.init(ctx.allocator(), .{
            .placeholder = "Paste BGG API token",
        });
        try self.hot_games.initInputs(ctx.allocator());
        try self.search.initInputs(ctx.allocator());
        try self.collection.initInputs(ctx.allocator(), self.config.collection.default_username);
        try self.settings.initInputs(ctx.allocator(), self.config.collection.default_username);
        self.requestMotionFrameIfNeeded(ctx);
    }

    pub fn update(self: *App, msg: Msg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .setup_token => |setup_msg| try self.updateSetupToken(setup_msg, ctx),
            .hot_games => |hot_msg| try self.updateHotGames(hot_msg, ctx),
            .search => |search_msg| try self.updateSearch(search_msg, ctx),
            .collection => |collection_msg| try self.updateCollection(collection_msg, ctx),
            .game_detail => |detail_msg| try self.updateGameDetail(detail_msg, ctx),
            .list_image => |image_msg| try self.updateListImage(image_msg, ctx),
            .forum => |forum_msg| try self.updateForum(forum_msg, ctx),
            .thread => |thread_msg| try self.updateThread(thread_msg, ctx),
            .browser => |browser_msg| try self.updateBrowser(browser_msg),
            .settings => |settings_msg| try self.updateSettings(settings_msg, ctx),
            .terminal_resized => |size| try self.handleResize(size),
            .frame => |frame| {
                self.animation_frame = frame.index;
                const transition_was_active = self.hasActiveScreenTransition();
                self.stepScreenTransition();
                if (transition_was_active and !self.hasActiveScreenTransition()) {
                    try self.startDeferredGameDetailTerminalImageLoad(ctx);
                    try self.syncListImagePreview(ctx);
                }
                try self.maybeStartSettledListImageDownload(ctx);
                self.requestMotionFrameIfNeeded(ctx);
            },
            .menu => |menu_msg| switch (menu_msg) {
                .move_prev, .move_next => self.menu.update(menu_msg),
                .activate => |index| {
                    if (screenForMenuIndex(index)) |screen| try self.showScreen(screen, ctx);
                },
            },
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

        if (self.hasActiveScreenTransition()) {
            motion.applyScreenTransition(sfc, self.screen_transition);
        }
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        if (event == .frame) return .{ .frame = event.frame };
        if (event == .winsize) {
            return .{ .terminal_resized = .{ .width = event.winsize.cols, .height = event.winsize.rows } };
        }

        if (self.screen == .setup_token) {
            switch (event) {
                .key_press => |key| if (key.matches(chasen.Key.escape, .{})) return .quit,
                .paste => |text| return .{ .setup_token = .{ .paste = text } },
                else => {},
            }
            if (self.setup_token_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .setup_token = .{ .input = msg } };
            }
            return null;
        }

        if (self.screen == .search) {
            switch (event) {
                .key_press => |key| if (key.matches(chasen.Key.escape, .{})) return .{ .show_screen = .main_menu },
                .paste => |text| return .{ .search = .{ .paste = text } },
                else => {},
            }
            if (self.search.input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .search = .{ .input = msg } };
            }
            return null;
        }

        if (self.screen == .search_results) {
            switch (event) {
                .key_press => |key| {
                    if (self.search.filter_active) {
                        if (key.matches(chasen.Key.escape, .{})) return .{ .search = .filter_clear };
                        if (key.codepoint == 'b') return .{ .show_screen = .search };
                        if (key.matches(chasen.Key.enter, .{})) {
                            if (self.search.handleEvent(event)) |msg| return .{ .search = .{ .list = msg } };
                            return null;
                        }
                    } else if (key.codepoint == '/') {
                        return .{ .search = .filter_start };
                    } else {
                        if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .{ .show_screen = .search };
                        if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                        if (key.codepoint == 's') return .{ .search = .sort_toggle };
                        if (key.codepoint == 'q') return .quit;
                    }
                },
                .paste => |text| if (self.search.filter_active) return .{ .search = .{ .filter_paste = text } },
                else => {},
            }
            if (self.search.filter_active) {
                if (self.search.filter_input) |*input| {
                    if (input.handleEvent(event)) |msg| return .{ .search = .{ .filter_input = msg } };
                }
            }
            if (self.search.handleEvent(event)) |msg| return .{ .search = .{ .list = msg } };
            return null;
        }

        if (self.screen == .game_detail) {
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .{ .game_detail = .move_prev };
                    if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .{ .game_detail = .move_next };
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'b') return .{ .show_screen = self.navigation.detail_back_screen };
                    if (key.codepoint == 'f' and self.game_detail.load_state == .loaded and self.game_detail.games.len > 0) return .{ .forum = .open };
                    if (key.codepoint == 'o' and self.game_detail.load_state == .loaded and self.game_detail.games.len > 0) return .{ .game_detail = .open_browser };
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
                        return .{ .forum = if (self.forums.mode == .thread_list) .back_to_list else .back_to_detail };
                    }
                    if (self.forums.mode == .thread_list) {
                        if (key.codepoint == 'n' and self.forums.canOpenNextPage()) return .{ .forum = .next_page };
                        if (key.codepoint == 'p' and self.forums.canOpenPreviousPage()) return .{ .forum = .previous_page };
                        if (self.forums.thread_list.handleEvent(event)) |msg| return .{ .forum = .{ .thread_list = msg } };
                    } else if (self.forums.mode == .forum_list) {
                        if (self.forums.forum_list.handleEvent(event)) |msg| return .{ .forum = .{ .list = msg } };
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
                    if (key.codepoint == 'b') return .{ .thread = .back_to_forums };
                    if (self.thread.load_state == .loaded) {
                        if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .{ .thread = .move_prev };
                        if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .{ .thread = .move_next };
                        if (key.codepoint == 's') return .{ .thread = .sort_toggle };
                        if (key.codepoint == 'o') return .{ .thread = .open_browser };
                    }
                },
                else => {},
            }
            return null;
        }

        if (self.screen == .collection) {
            if (self.collection.status_picker) {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) return .{ .collection = .status_close };
                        if (key.matches(chasen.Key.up, .{}) or key.codepoint == 'k') return .{ .collection = .status_move_prev };
                        if (key.matches(chasen.Key.down, .{}) or key.codepoint == 'j') return .{ .collection = .status_move_next };
                        if (key.matches(chasen.Key.enter, .{})) return .{ .collection = .status_toggle };
                    },
                    else => {},
                }
                return null;
            }
            if (self.collection.filter_active) {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) return .{ .collection = .filter_clear };
                        if (key.matches(chasen.Key.enter, .{})) {
                            if (self.collection.handleEvent(event)) |msg| return .{ .collection = .{ .list = msg } };
                            return null;
                        }
                    },
                    .paste => |text| return .{ .collection = .{ .filter_paste = text } },
                    else => {},
                }
                if (self.collection.filter_input) |*input| {
                    if (input.handleEvent(event)) |msg| return .{ .collection = .{ .filter_input = msg } };
                }
                if (self.collection.handleEvent(event)) |msg| return .{ .collection = .{ .list = msg } };
                return null;
            }
            switch (event) {
                .key_press => |key| {
                    if (self.collection.load_state == .loaded) {
                        if (key.codepoint == 's') return .{ .collection = .status_open };
                        if (key.codepoint == '/') return .{ .collection = .filter_start };
                        if (key.codepoint == 'u') return .{ .collection = .change_user };
                        if (key.codepoint == 'r') return .{ .collection = .refresh };
                        if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'm') return .{ .show_screen = .main_menu };
                        if (key.codepoint == 'q') return .quit;
                    } else if (key.matches(chasen.Key.escape, .{})) {
                        return .{ .show_screen = .main_menu };
                    }
                },
                .paste => |text| if (self.collection.load_state != .loaded) return .{ .collection = .{ .username_paste = text } },
                else => {},
            }
            if (self.collection.load_state == .loaded) {
                if (self.collection.handleEvent(event)) |msg| return .{ .collection = .{ .list = msg } };
            } else if (self.collection.username_input) |*input| {
                if (input.handleEvent(event)) |msg| return .{ .collection = .{ .username_input = msg } };
            }
            return null;
        }

        if (self.screen == .settings) {
            if (self.settings.editing) |field| {
                switch (event) {
                    .key_press => |key| {
                        if (key.matches(chasen.Key.escape, .{})) {
                            return switch (field) {
                                .token => .{ .settings = .token_cancel },
                                .username => .{ .settings = .username_cancel },
                                .list_width, .thread_width, .detail_width => .{ .settings = .width_cancel },
                            };
                        }
                        if (key.matches(chasen.Key.enter, .{})) {
                            return switch (field) {
                                .token => .{ .settings = .token_submit },
                                .username => .{ .settings = .username_submit },
                                .list_width, .thread_width, .detail_width => .{ .settings = .width_submit },
                            };
                        }
                    },
                    .paste => |text| {
                        return switch (field) {
                            .token => .{ .settings = .{ .token_paste = text } },
                            .username => .{ .settings = .{ .username_paste = text } },
                            .list_width, .thread_width, .detail_width => .{ .settings = .{ .width_paste = text } },
                        };
                    },
                    else => {},
                }
                switch (field) {
                    .token => if (self.settings.token_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings = .{ .token_input = msg } };
                    },
                    .username => if (self.settings.username_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings = .{ .username_input = msg } };
                    },
                    .list_width, .thread_width, .detail_width => if (self.settings.width_input) |*input| {
                        if (input.handleEvent(event)) |msg| return .{ .settings = .{ .width_input = msg } };
                    },
                }
                return null;
            }
            switch (event) {
                .key_press => |key| {
                    if (key.matches(chasen.Key.enter, .{})) {
                        if (self.settings.isShowImagesFocused()) return .{ .settings = .show_images_toggle };
                        if (self.settings.focusedCycleField()) |field| return .{ .settings = .{ .cycle_next = field } };
                        if (self.settings.focusedEditField()) |field| {
                            return switch (field) {
                                .token => .{ .settings = .token_start },
                                .username => .{ .settings = .username_start },
                                .list_width, .thread_width, .detail_width => .{ .settings = .{ .width_start = field } },
                            };
                        }
                    }
                    if (key.codepoint == 'm') return .{ .show_screen = .main_menu };
                    if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'q') return .quit;
                },
                else => {},
            }
            if (self.settings.handleEvent(event)) |msg| return .{ .settings = .{ .list = msg } };
            return null;
        }

        if (self.screen == .hot_games) {
            if (self.hot_games.handleScreenEvent(event)) |msg| return .{ .hot_games = msg };
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
        var area = layout_mod.centeredSurface(sfc, setup_token_size);
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
        var area = layout_mod.centeredSurface(sfc, main_menu_size);
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
            .show_cursor = false,
        });
        if (self.menu.focusedItem()) |item| {
            const row: u16 = @intCast(self.menu.focusedIndex());
            motion.drawFocusedText(&menu_area, 2, row, item.label, self.theme().focused, self.config.interface.selection, self.animation_frame);
        }

        ui.message_block.drawCenteredText(&area, 10, self.footerHint(), self.subtleStyle());
    }

    fn viewPlaceholder(self: *const App, sfc: *chasen.Surface, title: []const u8, message: []const u8) void {
        var area = layout_mod.centeredSurface(sfc, placeholder_size);
        _ = area.borrowTextAt(0, 0, title, self.titleStyle());
        _ = area.borrowTextAt(0, 2, message, self.mutedStyle());
        _ = area.borrowTextAt(0, 4, self.footerHint(), self.subtleStyle());
    }

    fn viewSettings(self: *const App, sfc: *chasen.Surface) !void {
        var area = layout_mod.centeredSurface(sfc, screens.settings.required_size);
        try self.settings.view(&area, self.config, self.config_path, self.theme(), self.config.interface.selection, self.animation_frame);
    }

    fn viewHotGames(self: *const App, sfc: *chasen.Surface) !void {
        var area = layout_mod.listSurface(sfc, self.config.display.list_width);
        const image_panel_rect = try self.hot_games.view(&area, .{
            .title_style = self.titleStyle(),
            .focused_style = self.focusedStyle(),
            .muted_style = self.mutedStyle(),
            .subtle_style = self.subtleStyle(),
            .footer_hint = self.footerHint(),
            .list_density = self.listDensity(),
            .selection = self.config.interface.selection,
            .animation_frame = self.animation_frame,
            .loading_scan_frame = self.loadingScanFrame(),
            .image_panel_rect = self.hotListImagePanelRect(&area),
            .image_panel_gap = list_image_panel_gap,
        });
        if (image_panel_rect) |rect| {
            try self.drawListImagePanel(&area, rect);
        }
    }

    fn viewSearch(self: *const App, sfc: *chasen.Surface) !void {
        var area = layout_mod.centeredSurface(sfc, search_input_size);
        _ = area.borrowTextAt(0, 0, "Search Games", self.titleStyle());

        if (self.search.input) |*input| {
            var input_area = area.child(.{ .col = 0, .row = 2, .width = @min(area.size().width, 48), .height = 1 });
            input.view(&input_area, .{});
        }

        switch (self.search.load_state) {
            .idle => {
                self.drawGuidance(&area, 4, "Search board games", "Enter at least 3 characters and press Enter.");
            },
            .loading => {
                self.drawLoadingGuidance(&area, 4, "Search board games", "Search request is running...");
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
        var area = layout_mod.listSurface(sfc, self.config.display.list_width);
        _ = try area.printAt(0, 0, self.titleStyle(), "Search Results ({s})", .{self.search.sort_mode.label(.search_results)});

        switch (self.search.load_state) {
            .idle => {
                self.drawCenteredGuidance(&area, "No search yet", "Run a search to see matching board games.");
            },
            .loading => {
                self.drawCenteredLoadingGuidance(&area, "Search Results", "Searching BoardGameGeek...");
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
                    list_view.viewListWithDensitySelection(list, &list_area, .{
                        .focused_style = self.focusedStyle(),
                        .show_cursor = false,
                    }, self.listDensity(), self.config.interface.selection, self.animation_frame);
                    try self.drawListPosition(&area, list);
                    self.drawSortMode(&area, self.search.sort_mode.label(.search_results));
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewCollection(self: *const App, sfc: *chasen.Surface) !void {
        var area = switch (self.collection.load_state) {
            .idle, .failed => layout_mod.centeredSurface(sfc, collection_input_size),
            else => layout_mod.listSurface(sfc, self.config.display.list_width),
        };
        _ = area.borrowTextAt(0, 0, "Collection", self.titleStyle());

        switch (self.collection.load_state) {
            .idle => {
                try self.drawCollectionUsernameInput(&area);
                self.drawGuidance(&area, 4, "Load collection", "Enter a BGG username and press Enter.");
            },
            .loading => {
                self.drawCenteredLoadingGuidance(&area, "Collection", "Loading BoardGameGeek collection...");
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
                    const picker_height = if (self.collection.status_picker) collection_status_picker_lines + collection_status_picker_gap else 0;
                    const image_panel_rect = self.collectionListImagePanelRect(&area);
                    const list_width = if (image_panel_rect) |rect| rect.col -| list_image_panel_gap else area.size().width;
                    var list_area = area.child(.{
                        .col = 0,
                        .row = body_row,
                        .width = list_width,
                        .height = area.size().height -| (body_row + 1 + list_footer_gap + picker_height),
                    });
                    list_view.viewListWithDensitySelection(list, &list_area, .{
                        .focused_style = self.focusedStyle(),
                        .show_cursor = false,
                    }, self.listDensity(), self.config.interface.selection, self.animation_frame);
                    if (image_panel_rect) |rect| {
                        try self.drawListImagePanel(&area, rect);
                    }
                    try self.drawListPositionWithLegend(&area, list, "games  ♥ User Rating  ★ Rating  #Rank");
                }
                if (self.collection.status_picker) {
                    const picker_row = area.size().height -| (collection_status_picker_lines + 1);
                    self.drawCollectionStatusPicker(&area, @max(collection_body_row, picker_row));
                }
            },
        }

        _ = area.borrowTextAt(0, area.size().height -| 1, self.footerHint(), self.subtleStyle());
    }

    fn viewGameDetail(self: *const App, sfc: *chasen.Surface) !void {
        sfc.hideCursor();
        var area = layout_mod.detailSurface(sfc, self.config.display.detail_width);

        switch (self.game_detail.load_state) {
            .idle, .loading => {
                self.drawCenteredLoadingGuidance(&area, "Game Details", "Loading game detail...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load game detail.", message);
            },
            .loaded => {
                const detail_layout = layout_mod.detailLayout(area.size().height, self.config.interface.list_density);
                const image_panel_rect = self.detailImagePanelRect(&area, detail_layout);
                const text_width = if (image_panel_rect) |rect| rect.col -| detail_image_panel_gap else area.size().width;
                var text_area = area.child(.{
                    .col = 0,
                    .row = 0,
                    .width = text_width,
                    .height = area.size().height,
                });

                if (self.game_detail.games.len == 0) {
                    self.drawEmptyState(&text_area, detail_layout.content_row, "No detail", "BGG did not return game detail.");
                } else {
                    const range = self.game_detail.visibleRange(detail_layout.content_height);
                    for (self.game_detail.lines[range.start..range.end], 0..) |line, index| {
                        const row = detail_layout.content_row + @as(u16, @intCast(index));
                        if (index >= detail_layout.content_height or row >= text_area.size().height) break;
                        _ = text_area.borrowTextAt(0, row, line, screens.detail.lineStyle(line));
                    }

                    if (self.game_detail.browser_error_url.len > 0) {
                        try self.drawManualOpenHint(&text_area, detail_layout.scroll_row, self.game_detail.browser_error_url);
                    } else if (self.game_detail.maxScroll(detail_layout.content_height) > 0 and text_area.size().height >= 3) {
                        _ = try text_area.printAt(0, detail_layout.scroll_row, .{ .dim = true }, "({d}/{d})", .{
                            self.game_detail.scroll + 1,
                            self.game_detail.maxScroll(detail_layout.content_height) + 1,
                        });
                    }
                }

                if (image_panel_rect) |rect| {
                    try self.drawDetailImagePanel(&area, rect);
                }
            },
        }

        const detail_layout = layout_mod.detailLayout(area.size().height, self.config.interface.list_density);
        _ = area.borrowTextAt(0, detail_layout.footer_row, self.footerHint(), self.subtleStyle());
    }

    fn viewForums(self: *const App, sfc: *chasen.Surface) !void {
        var area = layout_mod.forumSurface(sfc);

        switch (self.forums.load_state) {
            .idle, .loading_forums => {
                const title = try std.fmt.allocPrint(area.frameAllocator(), "{s} - Forums", .{self.forums.game_name});
                self.drawCenteredLoadingGuidance(&area, title, "Loading BoardGameGeek forums...");
            },
            .forums_loaded => {
                if (self.forums.forum_list.items.len == 0) {
                    self.drawCenteredGuidance(&area, "No forums", "BGG did not return forums for this game.");
                } else {
                    var forum_area = layout_mod.forumListSurface(&area, self.forums.forum_list.items.len, list_body_row);
                    const title = try std.fmt.allocPrint(forum_area.frameAllocator(), "{s} - Forums", .{self.forums.game_name});
                    ui.message_block.drawCenteredText(&forum_area, 0, title, self.titleStyle());
                    try self.drawCenteredListPosition(&forum_area, &self.forums.forum_list);
                    try self.drawCenteredForumList(&forum_area);
                    ui.message_block.drawCenteredText(&forum_area, forum_area.size().height -| 1, self.footerHint(), self.subtleStyle());
                }
            },
            .loading_threads => {
                self.drawCenteredLoadingGuidance(&area, self.forumThreadTitle(), "Loading BoardGameGeek threads...");
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

    fn drawDetailImagePanel(self: *const App, area: *chasen.Surface, rect: chasen.Rect) !void {
        var panel_area = area.child(rect);
        panel_area.clearAll();

        const frame = ui.Panel.frame(&panel_area, .{
            .title = "Cover",
            .border = self.panelBorder(),
            .border_style = self.theme().border,
            .title_style = self.theme().title,
        });
        frame.view();

        var content = frame.contentSurface();
        content.clearAll();

        if (self.game_detail.terminal_image_handle) |handle| {
            content.drawTerminalImage(handle, .{
                .fit = .fit,
                .horizontal_align = .center,
                .vertical_align = .middle,
                .z_index = 1,
            }) catch {
                self.drawCenteredLabel(&content, "Could not draw image", self.subtleStyle());
            };
            return;
        }

        const label = switch (self.game_detail.image_state) {
            .idle, .loading, .cached => if (self.game_detail.terminal_image_load_error) |reason|
                detailImageLoadErrorText(reason)
            else
                "Loading cover...",
            .disabled => "Images disabled",
            .unavailable => "No cover image",
            .failed => |message| message,
        };
        self.drawCenteredLabel(&content, label, self.subtleStyle());
    }

    fn drawListImagePanel(self: *const App, area: *chasen.Surface, rect: chasen.Rect) !void {
        var panel_area = area.child(rect);
        panel_area.clearAll();

        const frame = ui.Panel.frame(&panel_area, .{
            .title = "Preview",
            .border = self.panelBorder(),
            .border_style = self.theme().border,
            .title_style = self.theme().title,
        });
        frame.view();

        var content = frame.contentSurface();
        content.clearAll();

        if (self.list_image.terminal_image_handle) |handle| {
            content.drawTerminalImage(handle, .{
                .fit = .fit,
                .horizontal_align = .center,
                .vertical_align = .middle,
                .z_index = 1,
            }) catch {
                self.drawCenteredLabel(&content, "Could not draw image", self.subtleStyle());
            };
            return;
        }

        const label = switch (self.list_image.image_state) {
            .idle, .loading, .cached => if (self.list_image.terminal_image_load_error) |reason|
                detailImageLoadErrorText(reason)
            else
                "Loading cover...",
            .disabled => "Images disabled",
            .unavailable => "No cover image",
            .failed => |message| listImagePanelMessage(message),
        };
        self.drawCenteredLabel(&content, label, self.subtleStyle());
    }

    fn drawCenteredLabel(self: *const App, surface: *chasen.Surface, text: []const u8, style: chasen.TextStyle) void {
        _ = self;
        const size = surface.size();
        if (size.width == 0 or size.height == 0) return;
        const width = @min(chasen.text.displayWidth(text), size.width);
        const col: u16 = @intCast((size.width - width) / 2);
        const row: u16 = size.height / 2;
        _ = surface.borrowTextAt(col, row, text, style);
    }

    fn detailImagePanelRect(self: *const App, area: *const chasen.Surface, detail_layout: screens.detail.Layout) ?chasen.Rect {
        return layout_mod.detailImagePanelRectForSize(self.config, area.size(), detail_layout);
    }

    fn hotListImagePanelRect(self: *const App, area: *const chasen.Surface) ?chasen.Rect {
        return layout_mod.listImagePanelRectForSize(self.config, area.size(), list_body_row, null);
    }

    fn collectionListImagePanelRect(self: *const App, area: *const chasen.Surface) ?chasen.Rect {
        const picker_row: ?u16 = if (self.collection.status_picker)
            @max(collection_body_row, area.size().height -| (collection_status_picker_lines + 1))
        else
            null;
        return layout_mod.listImagePanelRectForSize(self.config, area.size(), collection_body_row, picker_row);
    }

    fn effectiveDetailContentWidth(self: *const App) usize {
        return layout_mod.detailContentWidthForSize(
            self.config,
            layout_mod.detailSurfaceSizeForTerminal(self.config, self.terminal_size),
            self.config.interface.list_density,
        );
    }

    fn viewThread(self: *const App, sfc: *chasen.Surface) !void {
        var area = layout_mod.threadSurface(sfc, self.config.display.thread_width);

        switch (self.thread.load_state) {
            .idle, .loading => {
                self.drawCenteredLoadingGuidance(&area, "Thread", "Loading thread...");
            },
            .failed => |message| {
                self.drawCenteredGuidance(&area, "Could not load thread.", message);
            },
            .loaded => {
                const thread_layout = layout_mod.threadLayout(area.size().height, self.config.interface.list_density);
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

        const thread_layout = layout_mod.threadLayout(area.size().height, self.config.interface.list_density);
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
        try self.showScreen(.main_menu, ctx);
    }

    fn updateSetupToken(self: *App, msg: SetupTokenMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitToken(ctx);
                } else if (self.setup_token_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .paste => |text| {
                if (self.setup_token_input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
        }
    }

    fn updateSettings(self: *App, msg: screens.settings.Msg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .token_start => try self.startSettingsTokenEdit(),
            .token_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsToken(ctx);
                } else if (self.settings.token_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .token_paste => |text| {
                if (self.settings.token_input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
            .token_submit => try self.submitSettingsToken(ctx),
            .token_cancel => self.cancelSettingsTokenEdit(),
            .username_start => try self.startSettingsUsernameEdit(),
            .username_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsUsername(ctx);
                } else if (self.settings.username_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .username_paste => |text| {
                if (self.settings.username_input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
            .username_submit => try self.submitSettingsUsername(ctx),
            .username_cancel => self.cancelSettingsUsernameEdit(),
            .width_start => |field| try self.startSettingsWidthEdit(field),
            .width_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.submitSettingsWidth(ctx);
                } else if (self.settings.width_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .width_paste => |text| {
                if (self.settings.width_input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
            .width_submit => try self.submitSettingsWidth(ctx),
            .width_cancel => self.cancelSettingsWidthEdit(),
            .show_images_toggle => try self.toggleSettingsShowImages(ctx),
            .cycle_next => |field| try self.cycleSettingsField(ctx, field),
            .list => |list_msg| self.settings.updateList(list_msg),
        }
    }

    fn startSettingsTokenEdit(self: *App) !void {
        if (self.settings.token_input) |*input| {
            try input.update(.clear);
        }
        self.settings.startEdit(.token);
    }

    fn submitSettingsToken(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.settings.token_input) |*input| input else return;
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
        if (self.settings.token_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn startSettingsUsernameEdit(self: *App) !void {
        if (self.settings.username_input) |*input| {
            try input.update(.clear);
            if (self.config.collection.default_username) |username| {
                try paste.insertCodepoints(input, username);
            }
        }
        self.settings.startEdit(.username);
    }

    fn submitSettingsUsername(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.settings.username_input) |*input| input else return;
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
        if (self.settings.username_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn startSettingsWidthEdit(self: *App, field: screens.settings.EditField) !void {
        if (self.settings.width_input) |*input| {
            try input.update(.clear);
            try inputWidthValue(input, self.config, field);
        }
        self.settings.startEdit(field);
    }

    fn submitSettingsWidth(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const field = self.settings.editing orelse return;
        const input = if (self.settings.width_input) |*input| input else return;
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
        if (self.settings.width_input) |*input| {
            input.update(.clear) catch {};
        }
        self.settings.stopEditing();
    }

    fn toggleSettingsShowImages(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.config.display.show_images = !self.config.display.show_images;
        try self.syncListImagePreview(ctx);
        try self.saveConfigIfAvailable(ctx);
    }

    fn cycleSettingsField(self: *App, ctx: *chasen.Ctx(Msg), field: screens.settings.CycleField) !void {
        switch (field) {
            .color_theme => self.config.interface.color_theme = nextCycleValue(self.config.interface.color_theme, &color_theme_values),
            .transition => {
                self.config.interface.transition = nextCycleValue(self.config.interface.transition, &transition_values);
                self.startContentTransition(ctx);
            },
            .selection => {
                self.config.interface.selection = nextCycleValue(self.config.interface.selection, &selection_values);
                self.requestMotionFrameIfNeeded(ctx);
            },
            .border_style => self.config.interface.border_style = nextCycleValue(self.config.interface.border_style, &border_style_values),
            .list_density => self.config.interface.list_density = nextCycleValue(self.config.interface.list_density, &list_density_values),
            .date_format => self.config.interface.date_format = nextCycleValue(self.config.interface.date_format, &date_format_values),
            .image_protocol => {
                self.config.display.image_protocol = nextImageProtocol(self.config.display.image_protocol);
                try self.syncListImagePreview(ctx);
            },
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
        self.hot_games.deinitInputs();
        self.search.deinitInputs();
        self.collection.deinitInputs();
        self.settings.deinitInputs();
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
        self.releaseListImageTerminalImage(null);
        self.list_image.reset(self.allocator.?);
        self.forums.deinit(self.allocator.?);
        self.thread.deinit(self.allocator.?);
    }

    fn updateHotGames(self: *App, msg: HotGamesMsg, ctx: *chasen.Ctx(Msg)) !void {
        const action = try self.hot_games.updateScreen(self.allocator.?, msg);
        switch (action) {
            .none => {},
            .preview_changed => try self.syncListImagePreview(ctx),
            .open_game => |source_index| try self.openHotGame(source_index, ctx),
            .loaded => |result| try self.finishHotGamesLoad(ctx, result),
            .stats_loaded => |result| try self.finishHotGameStatsLoad(result),
        }
    }

    fn updateSearch(self: *App, msg: SearchMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .input => |input_msg| {
                if (input_msg == .submit) {
                    try self.startSearch(ctx);
                } else if (self.search.input) |*input| {
                    try input.update(input_msg);
                }
            },
            .paste => |text| {
                if (self.search.input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
            .filter_start => try self.startSearchFilter(),
            .filter_input => |input_msg| {
                if (input_msg != .submit) {
                    if (self.search.filter_input) |*input| try input.update(input_msg);
                    try self.applySearchFilter();
                }
            },
            .filter_paste => |text| {
                if (self.search.filter_input) |*input| {
                    try paste.insertCodepoints(input, text);
                    try self.applySearchFilter();
                }
            },
            .filter_clear => try self.clearSearchFilter(),
            .sort_toggle => try self.toggleSearchSort(),
            .results_loaded => |result| try self.finishSearch(ctx, result),
            .list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.search.update(list_msg),
                .activate => |index| {
                    if (self.search.sourceIndex(index)) |source_index| try self.openSearchResult(source_index, ctx);
                },
            },
        }
    }

    fn startSearchFilter(self: *App) !void {
        if (self.search.filter_input) |*input| try input.update(.clear);
        try self.search.applyFilter(self.allocator.?, "");
    }

    fn applySearchFilter(self: *App) !void {
        const input = if (self.search.filter_input) |*input| input else return;
        try self.search.applyFilter(self.allocator.?, input.text());
    }

    fn clearSearchFilter(self: *App) !void {
        if (self.search.filter_input) |*input| try input.update(.clear);
        self.search.clearFilter(self.allocator.?);
    }

    fn toggleSearchSort(self: *App) !void {
        try self.search.toggleSort(self.allocator.?);
    }

    fn updateCollection(self: *App, msg: CollectionMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .username_input => |input_msg| {
                if (input_msg == .submit) {
                    try self.startCollectionLoad(ctx);
                } else if (self.collection.username_input) |*input| {
                    try input.update(input_msg);
                }
            },
            .username_paste => |text| {
                if (self.collection.username_input) |*input| {
                    try paste.insertCodepoints(input, text);
                }
            },
            .filter_start => {
                try self.startCollectionFilter();
                try self.syncListImagePreview(ctx);
            },
            .filter_input => |input_msg| {
                if (input_msg != .submit) {
                    if (self.collection.filter_input) |*input| try input.update(input_msg);
                    try self.applyCollectionFilter();
                    try self.syncListImagePreview(ctx);
                }
            },
            .filter_paste => |text| {
                if (self.collection.filter_input) |*input| {
                    try paste.insertCodepoints(input, text);
                    try self.applyCollectionFilter();
                    try self.syncListImagePreview(ctx);
                }
            },
            .filter_clear => {
                try self.clearCollectionFilter();
                try self.syncListImagePreview(ctx);
            },
            .change_user => {
                try self.changeCollectionUser();
                try self.syncListImagePreview(ctx);
            },
            .refresh => {
                try self.refreshCollection(ctx);
                try self.syncListImagePreview(ctx);
            },
            .status_open => self.openCollectionStatusPicker(),
            .status_move_prev => self.moveCollectionStatusCursor(.prev),
            .status_move_next => self.moveCollectionStatusCursor(.next),
            .status_toggle => try self.toggleCollectionStatus(ctx),
            .status_close => self.collection.status_picker = false,
            .items_loaded => |result| try self.finishCollectionLoad(ctx, result),
            .list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => {
                    self.collection.update(list_msg);
                    try self.syncListImagePreview(ctx);
                },
                .activate => |index| {
                    if (self.collection.sourceIndex(index)) |source_index| try self.openCollectionItem(source_index, ctx);
                },
            },
        }
    }

    fn updateGameDetail(self: *App, msg: GameDetailMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .loaded => |result| try self.finishGameDetail(ctx, result),
            .image_cached => |result| try self.finishGameDetailImageCache(ctx, result),
            .terminal_image_loaded => |result| self.finishGameDetailTerminalImageLoad(ctx, result),
            .terminal_image_failed => |result| self.finishGameDetailTerminalImageFailure(result),
            .move_prev => self.game_detail.moveUp(),
            .move_next => self.game_detail.moveDown(self.game_detail.visible_height),
            .open_browser => try self.openGameInBrowser(ctx),
        }
    }

    fn updateListImage(self: *App, msg: ListImageMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .image_cached => |result| try self.finishListImageCache(ctx, result),
            .terminal_image_loaded => |result| self.finishListImageTerminalImageLoad(ctx, result),
            .terminal_image_failed => |result| self.finishListImageTerminalImageFailure(result),
        }
    }

    fn updateForum(self: *App, msg: ForumMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .open => try self.startForumList(ctx),
            .loaded => |result| try self.finishForumList(ctx, result),
            .list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.forums.updateForumList(list_msg),
                .activate => |index| try self.startForumThreads(ctx, index, 1),
            },
            .threads_loaded => |result| try self.finishForumThreads(ctx, result),
            .thread_list => |list_msg| switch (list_msg) {
                .move_prev, .move_next => self.forums.updateThreadList(list_msg),
                .activate => |index| try self.startThread(ctx, index),
            },
            .back_to_detail => try self.showScreen(.game_detail, ctx),
            .back_to_list => self.backToForumList(),
            .next_page => try self.openForumPage(ctx, self.forums.thread_page.page + 1),
            .previous_page => try self.openForumPage(ctx, self.forums.thread_page.page -| 1),
        }
    }

    fn updateThread(self: *App, msg: ThreadMsg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .loaded => |result| try self.finishThread(ctx, result),
            .move_prev => self.thread.moveUp(),
            .move_next => self.thread.moveDown(threadLayoutForTerminal(self).content_height),
            .sort_toggle => try self.thread.toggleSort(self.allocator.?),
            .open_browser => try self.openThreadInBrowser(ctx),
            .back_to_forums => self.backToThreadList(ctx),
        }
    }

    fn updateBrowser(self: *App, msg: BrowserMsg) !void {
        switch (msg) {
            .opened => |result| try self.finishBrowserOpen(result),
        }
    }

    fn startCollectionFilter(self: *App) !void {
        if (self.collection.filter_input) |*input| try input.update(.clear);
        try self.collection.applyFilter(self.allocator.?, "");
    }

    fn applyCollectionFilter(self: *App) !void {
        const input = if (self.collection.filter_input) |*input| input else return;
        try self.collection.applyFilter(self.allocator.?, input.text());
    }

    fn clearCollectionFilter(self: *App) !void {
        if (self.collection.filter_input) |*input| try input.update(.clear);
        self.collection.clearFilter(self.allocator.?);
    }

    fn changeCollectionUser(self: *App) !void {
        self.collection.request_id +%= 1;
        self.collection.status_picker = false;
        if (self.collection.filter_input) |*input| try input.update(.clear);
        self.collection.deinit(self.allocator.?);
    }

    fn refreshCollection(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.collection.filter_input) |*input| try input.update(.clear);
        self.collection.clearFilter(self.allocator.?);
        try self.startCollectionLoad(ctx);
    }

    const StatusMove = enum { prev, next };

    fn openCollectionStatusPicker(self: *App) void {
        self.collection.status_picker = true;
        self.collection.status_cursor = 0;
    }

    fn moveCollectionStatusCursor(self: *App, direction: StatusMove) void {
        switch (direction) {
            .prev => {
                if (self.collection.status_cursor > 0) self.collection.status_cursor -= 1;
            },
            .next => {
                if (self.collection.status_cursor < collection_picker_clear_index) self.collection.status_cursor += 1;
            },
        }
    }

    fn toggleCollectionStatus(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.collection.status_cursor == collection_picker_clear_index) {
            self.collection.status_mask = 0;
        } else {
            const bit = collectionStatusBit(self.collection.status_cursor);
            if ((self.collection.status_mask & bit) != 0) {
                self.collection.status_mask &= ~bit;
            } else {
                self.collection.status_mask |= bit;
            }
        }
        self.config.collection.status_filter.mask = self.collection.status_mask;
        try self.saveConfigIfAvailable(ctx);
        try self.collection.applyStatusFilter(self.allocator.?, self.collection.status_mask);
        try self.syncListImagePreview(ctx);
    }

    fn showScreen(self: *App, screen: Screen, ctx: *chasen.Ctx(Msg)) !void {
        const previous_screen = self.screen;
        self.screen = screen;
        self.startScreenTransition(previous_screen, screen, ctx);
        if (screen == .hot_games) {
            try self.startHotGamesLoad(ctx);
        }
        if (screen == .search and previous_screen != .search_results) {
            try self.resetSearchScreen();
        }
        if (screen == .game_detail) {
            try self.startDeferredGameDetailTerminalImageLoad(ctx);
        }
        try self.syncListImagePreview(ctx);
    }

    fn resetSearchScreen(self: *App) !void {
        if (self.search.input) |*input| {
            try input.update(.clear);
        }
        self.search.request_id +%= 1;
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
        if (self.hot_games.load_state == .loading) {
            self.switchScreenWithoutTransition(.hot_games);
            self.requestMotionFrameIfNeeded(ctx);
            return;
        }
        if (self.hot_games.load_state == .loaded) return;

        self.switchScreenWithoutTransition(.hot_games);

        const token = self.config.apiClientToken() orelse {
            self.hot_games.setFailed("BGG API token is required");
            return;
        };

        const task = try ctx.allocator().create(HotGamesTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{ .token = try ctx.allocator().dupe(u8, token) };
        errdefer ctx.allocator().free(task.token);

        self.hot_games.setLoading();
        self.beginLoadingMotion(ctx);
        ctx.spawnWith(task, HotGamesTask.run) catch |err| {
            self.hot_games.setFailed("Could not start hot games loading task");
            return err;
        };
    }

    fn finishHotGamesLoad(self: *App, ctx: *chasen.Ctx(Msg), result: HotGamesResult) !void {
        switch (result) {
            .ok => |games| {
                try self.hot_games.setLoaded(self.allocator.?, games);
                try self.syncListImagePreview(ctx);
                try self.startHotGameStatsLoad(ctx);
                self.startContentTransitionIfVisible(ctx, .hot_games);
            },
            .failed => |message| self.hot_games.setFailed(message),
        }
    }

    fn startHotGameStatsLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const token = self.config.apiClientToken() orelse return;
        const ids = try ctx.allocator().alloc(u32, self.hot_games.games.len);
        errdefer ctx.allocator().free(ids);
        for (self.hot_games.games, 0..) |game, index| ids[index] = game.id;

        const task = try ctx.allocator().create(HotGameStatsTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{
            .token = try ctx.allocator().dupe(u8, token),
            .ids = ids,
            .request_id = self.hot_games.request_id,
        };
        errdefer ctx.allocator().free(task.token);

        ctx.spawnWith(task, HotGameStatsTask.run) catch |err| {
            return err;
        };
    }

    fn finishHotGameStatsLoad(self: *App, task_result: HotGameStatsResult) !void {
        if (task_result.request_id != self.hot_games.request_id) {
            switch (task_result.result) {
                .ok => |stats| bgg_xml.freeGames(self.allocator.?, stats),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |stats| try self.hot_games.setStatsLoaded(self.allocator.?, stats),
            .failed => {}, // Supplemental stats should not make the already-loaded list unusable.
        }
    }

    fn startSearch(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.search.input) |*input| input else return;
        const query = std.mem.trim(u8, input.text(), " \t\r\n");
        // Every submit represents the current search intent. Bump the request
        // id before validation so older in-flight tasks cannot replace a new
        // validation or auth failure state.
        self.search.request_id +%= 1;
        const request_id = self.search.request_id;

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

        self.search.setLoading(self.allocator.?);
        self.switchScreenWithoutTransition(.search_results);
        self.beginLoadingMotion(ctx);
        ctx.spawnWith(task, SearchTask.run) catch |err| {
            self.search.setFailed(self.allocator.?, "Could not start search task");
            return err;
        };
    }

    fn finishSearch(self: *App, ctx: *chasen.Ctx(Msg), task_result: SearchTaskResult) !void {
        if (task_result.request_id != self.search.request_id) {
            switch (task_result.result) {
                .ok => |results| bgg_xml.freeSearchResults(self.allocator.?, results),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |results| {
                try self.search.setLoaded(self.allocator.?, results);
                self.startContentTransitionIfVisible(ctx, .search_results);
            },
            .failed => |message| self.search.setFailed(self.allocator.?, message),
        }
    }

    fn startCollectionLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const input = if (self.collection.username_input) |*input| input else return;
        const username = std.mem.trim(u8, input.text(), " \t\r\n");
        self.collection.request_id +%= 1;
        const request_id = self.collection.request_id;

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
        self.switchScreenWithoutTransition(.collection);
        self.beginLoadingMotion(ctx);
        ctx.spawnWith(task, CollectionTask.run) catch |err| {
            self.collection.setFailed(self.allocator.?, "Could not start collection loading task");
            return err;
        };
    }

    fn finishCollectionLoad(self: *App, ctx: *chasen.Ctx(Msg), task_result: CollectionTaskResult) !void {
        if (task_result.request_id != self.collection.request_id) {
            switch (task_result.result) {
                .ok => |items| bgg_xml.freeCollectionItems(self.allocator.?, items),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |items| {
                try self.collection.setLoaded(self.allocator.?, items, self.collection.status_mask);
                try self.syncListImagePreview(ctx);
                self.startContentTransitionIfVisible(ctx, .collection);
            },
            .failed => |message| self.collection.setFailed(self.allocator.?, message),
        }
    }

    fn startGameDetail(self: *App, ctx: *chasen.Ctx(Msg), game_id: u32, back_screen: Screen) !void {
        self.game_detail.request_id +%= 1;
        self.game_detail.image_request_id +%= 1;
        self.browser.request_id +%= 1;
        const request_id = self.game_detail.request_id;
        self.navigation.detail_back_screen = back_screen;
        self.releaseGameDetailTerminalImage(ctx);
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

        self.game_detail.setLoading(self.allocator.?);
        self.switchScreenWithoutTransition(.game_detail);
        self.beginLoadingMotion(ctx);
        ctx.spawnWith(task, GameDetailTask.run) catch |err| {
            self.game_detail.setFailed("Could not start game detail task");
            return err;
        };
    }

    fn finishGameDetail(self: *App, ctx: *chasen.Ctx(Msg), task_result: GameDetailTaskResult) !void {
        if (task_result.request_id != self.game_detail.request_id) {
            switch (task_result.result) {
                .ok => |games| bgg_xml.freeGames(self.allocator.?, games),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |games| {
                try self.game_detail.setLoaded(self.allocator.?, games, self.effectiveDetailContentWidth());
                self.game_detail.setVisibleHeight(detailLayoutForTerminal(self).content_height);
                try self.startGameDetailImageCache(ctx);
                self.startContentTransitionIfVisible(ctx, .game_detail);
            },
            .failed => |message| self.game_detail.setFailed(message),
        }
    }

    fn startGameDetailImageCache(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        self.game_detail.image_request_id +%= 1;
        const request_id = self.game_detail.image_request_id;

        if (!self.config.display.show_images or self.config.display.image_protocol == .off) {
            self.game_detail.setImageDisabled(self.allocator.?);
            return;
        }

        const cache_dir = self.image_cache_dir orelse {
            self.game_detail.setImageFailed(self.allocator.?, "Image cache directory is unavailable");
            return;
        };

        const url = self.gameDetailImageUrl() orelse {
            self.game_detail.setImageUnavailable(self.allocator.?);
            return;
        };
        if (!image_mod.canLoadTerminalImageFromUrl(url)) {
            self.game_detail.setImageFailed(self.allocator.?, detailUnsupportedImageFormatText(image_mod.sourceFormatFromUrl(url)));
            return;
        }

        const task = try ctx.allocator().create(GameDetailImageTask);
        errdefer ctx.allocator().destroy(task);

        task.* = .{
            .cache_dir = try ctx.allocator().dupe(u8, cache_dir),
            .url = try ctx.allocator().dupe(u8, url),
            .request_id = request_id,
        };
        errdefer ctx.allocator().free(task.cache_dir);
        errdefer ctx.allocator().free(task.url);

        self.game_detail.setImageLoading(self.allocator.?);
        ctx.spawnWith(task, GameDetailImageTask.run) catch |err| {
            self.game_detail.setImageFailed(self.allocator.?, "Could not start image cache task");
            return err;
        };
    }

    fn finishGameDetailImageCache(self: *App, ctx: *chasen.Ctx(Msg), task_result: GameDetailImageTaskResult) !void {
        if (task_result.request_id != self.game_detail.image_request_id) {
            switch (task_result.result) {
                .ok => |path| self.allocator.?.free(path),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |path| {
                self.game_detail.setImageCached(self.allocator.?, path);
                try self.startDeferredGameDetailTerminalImageLoad(ctx);
            },
            .failed => |message| self.game_detail.setImageFailed(self.allocator.?, message),
        }
    }

    fn startDeferredGameDetailTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.screen != .game_detail) return;
        if (self.hasActiveScreenTransition()) return;
        if (self.game_detail.terminal_image_handle != null or self.game_detail.terminal_image_load_error != null) return;

        const path = self.game_detail.imagePath() orelse return;
        try self.startGameDetailTerminalImageLoad(ctx, path);
    }

    fn startGameDetailTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg), path: []const u8) !void {
        self.releaseGameDetailTerminalImage(ctx);

        const load_ctx = try self.allocator.?.create(GameDetailTerminalImageLoadContext);
        errdefer self.allocator.?.destroy(load_ctx);
        load_ctx.* = .{ .request_id = self.game_detail.image_request_id };

        self.game_detail.setTerminalImageLoading();
        ctx.loadTerminalImagePath(path, load_ctx, &gameDetailTerminalImageLoaded, &gameDetailTerminalImageFailed) catch |err| {
            self.game_detail.setTerminalImageFailed(.load_failed);
            return err;
        };
    }

    fn finishGameDetailTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg), result: GameDetailTerminalImageLoaded) void {
        const load_ctx = result.load_ctx;
        defer self.allocator.?.destroy(load_ctx);

        if (load_ctx.request_id != self.game_detail.image_request_id) {
            ctx.unloadTerminalImage(result.handle) catch {};
            return;
        }

        self.game_detail.setTerminalImageLoaded(result.handle);
    }

    fn finishGameDetailTerminalImageFailure(self: *App, result: GameDetailTerminalImageFailed) void {
        const load_ctx = result.load_ctx;
        defer self.allocator.?.destroy(load_ctx);

        if (load_ctx.request_id != self.game_detail.image_request_id) return;
        self.game_detail.setTerminalImageFailed(result.reason);
    }

    fn releaseGameDetailTerminalImage(self: *App, ctx: *chasen.Ctx(Msg)) void {
        if (self.game_detail.terminal_image_handle) |handle| {
            ctx.unloadTerminalImage(handle) catch {};
            self.game_detail.terminal_image_handle = null;
        }
        self.game_detail.terminal_image_load_error = null;
    }

    fn syncListImagePreview(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        const allocator = self.allocator orelse ctx.allocator();
        const source = self.currentListImageSource();
        if (!layout_mod.detailWantsImagePanel(self.config)) {
            self.releaseListImageTerminalImage(ctx);
            _ = self.list_image.setSourceImmediate(allocator, null);
            self.list_image.setImageDisabled(allocator);
            return;
        }

        if (source == null) {
            self.releaseListImageTerminalImage(ctx);
            if (self.list_image.setSourceImmediate(allocator, null)) {}
            self.list_image.setImageUnavailable(allocator);
            return;
        }

        const image_source = source.?;
        if (!image_mod.canLoadTerminalImageFromUrl(image_source.url)) {
            self.releaseListImageTerminalImage(ctx);
            _ = self.list_image.setSourceImmediate(allocator, image_source);
            self.list_image.setImageFailed(allocator, detailUnsupportedImageFormatText(image_mod.sourceFormatFromUrl(image_source.url)));
            return;
        }

        if (features.list_image.sameOptionalSource(self.list_image.source, image_source)) {
            try self.startDeferredListImageTerminalImageLoad(ctx);
            try self.maybeStartSettledListImageDownload(ctx);
            return;
        }

        self.releaseListImageTerminalImage(ctx);
        _ = self.list_image.setSourceImmediate(allocator, image_source);

        const cache_dir = self.image_cache_dir orelse {
            self.list_image.setImageFailed(allocator, "Image cache directory is unavailable");
            return;
        };
        const path = try image_mod.cachePathForUrl(allocator, cache_dir, image_source.url);
        errdefer allocator.free(path);

        if (image_mod.cacheHit(ctx.io(), path)) {
            self.list_image.setImageCached(allocator, path);
            try self.startDeferredListImageTerminalImageLoad(ctx);
            return;
        }

        allocator.free(path);
        self.list_image.setImageLoading(allocator);
        _ = self.list_image.setCandidate(image_source, self.animation_frame);
        self.requestMotionFrameIfNeeded(ctx);
    }

    fn maybeStartSettledListImageDownload(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.hasActiveScreenTransition()) return;
        if (self.list_image.cache_task_pending) return;
        if (!self.list_image.candidateSettled(self.animation_frame)) {
            if (self.list_image.candidate != null) self.requestMotionFrameIfNeeded(ctx);
            return;
        }
        const source = self.list_image.candidate orelse return;
        if (!features.list_image.sameOptionalSource(self.list_image.source, source)) return;
        if (self.list_image.imagePath() != null or self.list_image.terminal_image_handle != null) return;

        try self.startListImageCache(ctx, source);
    }

    fn startListImageCache(self: *App, ctx: *chasen.Ctx(Msg), source: ListImageSource) !void {
        const cache_dir = self.image_cache_dir orelse {
            self.list_image.setImageFailed(self.allocator.?, "Image cache directory is unavailable");
            return;
        };

        const task = try ctx.allocator().create(ListImageTask);
        errdefer ctx.allocator().destroy(task);

        task.* = .{
            .cache_dir = try ctx.allocator().dupe(u8, cache_dir),
            .url = try ctx.allocator().dupe(u8, source.url),
            .request_id = self.list_image.request_id,
        };
        errdefer ctx.allocator().free(task.cache_dir);
        errdefer ctx.allocator().free(task.url);

        self.list_image.cache_task_pending = true;
        ctx.spawnWith(task, ListImageTask.run) catch |err| {
            self.list_image.cache_task_pending = false;
            self.list_image.setImageFailed(self.allocator.?, "Could not start image cache task");
            return err;
        };
    }

    fn finishListImageCache(self: *App, ctx: *chasen.Ctx(Msg), task_result: ListImageTaskResult) !void {
        if (task_result.request_id != self.list_image.request_id) {
            switch (task_result.result) {
                .ok => |path| self.allocator.?.free(path),
                .failed => {},
            }
            return;
        }

        self.list_image.cache_task_pending = false;
        switch (task_result.result) {
            .ok => |path| {
                self.list_image.setImageCached(self.allocator.?, path);
                try self.startDeferredListImageTerminalImageLoad(ctx);
            },
            .failed => |message| self.list_image.setImageFailed(self.allocator.?, message),
        }
    }

    fn startDeferredListImageTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (!isListImageScreen(self.screen)) return;
        if (self.hasActiveScreenTransition()) return;
        if (self.list_image.terminal_image_handle != null or self.list_image.terminal_image_load_error != null) return;

        const path = self.list_image.imagePath() orelse return;
        try self.startListImageTerminalImageLoad(ctx, path);
    }

    fn startListImageTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg), path: []const u8) !void {
        self.releaseListImageTerminalImage(ctx);

        const load_ctx = try self.allocator.?.create(ListImageTerminalImageLoadContext);
        errdefer self.allocator.?.destroy(load_ctx);
        load_ctx.* = .{ .request_id = self.list_image.request_id };

        self.list_image.setTerminalImageLoading();
        ctx.loadTerminalImagePath(path, load_ctx, &listImageTerminalImageLoaded, &listImageTerminalImageFailed) catch |err| {
            self.list_image.setTerminalImageFailed(.load_failed);
            return err;
        };
    }

    fn finishListImageTerminalImageLoad(self: *App, ctx: *chasen.Ctx(Msg), result: ListImageTerminalImageLoaded) void {
        const load_ctx = result.load_ctx;
        defer self.allocator.?.destroy(load_ctx);

        if (load_ctx.request_id != self.list_image.request_id) {
            ctx.unloadTerminalImage(result.handle) catch {};
            return;
        }

        self.list_image.setTerminalImageLoaded(result.handle);
    }

    fn finishListImageTerminalImageFailure(self: *App, result: ListImageTerminalImageFailed) void {
        const load_ctx = result.load_ctx;
        defer self.allocator.?.destroy(load_ctx);

        if (load_ctx.request_id != self.list_image.request_id) return;
        self.list_image.setTerminalImageFailed(result.reason);
    }

    fn releaseListImageTerminalImage(self: *App, ctx: ?*chasen.Ctx(Msg)) void {
        if (self.list_image.terminal_image_handle) |handle| {
            if (ctx) |ctx_ptr| ctx_ptr.unloadTerminalImage(handle) catch {};
            self.list_image.terminal_image_handle = null;
        }
        self.list_image.terminal_image_load_error = null;
    }

    fn currentListImageSource(self: *const App) ?ListImageSource {
        return switch (self.screen) {
            .hot_games => self.hotListImageSource(),
            .collection => self.collectionListImageSource(),
            else => null,
        };
    }

    fn hotListImageSource(self: *const App) ?ListImageSource {
        if (self.hot_games.load_state != .loaded) return null;
        const focused_index = self.hot_games.activeList().focusedIndex();
        const source_index = self.hot_games.sourceIndex(focused_index) orelse return null;
        const game = self.hot_games.games[source_index];
        const url = game.thumbnail_url orelse return null;
        return .{ .kind = .hot_games, .id = game.id, .url = url };
    }

    fn collectionListImageSource(self: *const App) ?ListImageSource {
        if (self.collection.load_state != .loaded) return null;
        const focused_index = self.collection.activeList().focusedIndex();
        const source_index = self.collection.sourceIndex(focused_index) orelse return null;
        const item = self.collection.items[source_index];
        const url = item.thumbnail_url orelse return null;
        return .{ .kind = .collection, .id = item.id, .url = url };
    }

    fn gameDetailImageUrl(self: *const App) ?[]const u8 {
        if (self.game_detail.load_state != .loaded or self.game_detail.games.len == 0) return null;
        const game = self.game_detail.games[0];
        if (game.image_url) |url| {
            if (url.len > 0) return url;
        }
        if (game.thumbnail_url) |url| {
            if (url.len > 0) return url;
        }
        return null;
    }

    fn openGameInBrowser(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.game_detail.load_state != .loaded or self.game_detail.games.len == 0) return;

        const game = self.game_detail.games[0];
        const url = try formatOwnedText(ctx.allocator(), format.writeBggGameUrl, .{game.id});
        errdefer ctx.allocator().free(url);

        self.browser.request_id +%= 1;
        const request_id = self.browser.request_id;

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
        self.forums.request_id +%= 1;
        self.forums.thread_list_request_id +%= 1;
        const request_id = self.forums.request_id;

        try self.forums.startForumLoad(self.allocator.?, game.id, game.name);
        self.switchScreenWithoutTransition(.forums);
        self.beginLoadingMotion(ctx);

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

    fn finishForumList(self: *App, ctx: *chasen.Ctx(Msg), task_result: ForumListTaskResult) !void {
        if (task_result.request_id != self.forums.request_id) {
            switch (task_result.result) {
                .ok => |forums| bgg_xml.freeForums(self.allocator.?, forums),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |forums| {
                try self.forums.setForumsLoaded(self.allocator.?, forums);
                self.startContentTransitionIfVisible(ctx, .forums);
            },
            .failed => |message| self.forums.setFailed(message),
        }
    }

    fn startForumThreads(self: *App, ctx: *chasen.Ctx(Msg), visible_index: usize, page: u32) !void {
        const forum = self.forums.selectedForumFromVisible(visible_index) orelse return;
        self.forums.thread_list_request_id +%= 1;
        const request_id = self.forums.thread_list_request_id;
        self.forums.startThreadLoad(self.allocator.?, visible_index);
        self.switchScreenWithoutTransition(.forums);
        self.beginLoadingMotion(ctx);
        try self.spawnForumThreadsTask(ctx, forum.id, page, request_id);
    }

    fn openForumPage(self: *App, ctx: *chasen.Ctx(Msg), page: u32) !void {
        const forum = self.forums.selectedForum() orelse return;
        self.forums.thread_list_request_id +%= 1;
        const request_id = self.forums.thread_list_request_id;
        self.forums.startThreadPageLoad(self.allocator.?, page);
        self.switchScreenWithoutTransition(.forums);
        self.beginLoadingMotion(ctx);
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

    fn finishForumThreads(self: *App, ctx: *chasen.Ctx(Msg), task_result: ForumThreadsTaskResult) !void {
        if (task_result.request_id != self.forums.thread_list_request_id) {
            switch (task_result.result) {
                .ok => |thread_page| bgg_xml.freeThreadList(self.allocator.?, thread_page),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |thread_page| {
                try self.forums.setThreadsLoaded(self.allocator.?, thread_page);
                self.startContentTransitionIfVisible(ctx, .forums);
            },
            .failed => |message| self.forums.setFailed(message),
        }
    }

    fn backToForumList(self: *App) void {
        self.forums.thread_list_request_id +%= 1;
        self.forums.backToForumList(self.allocator.?);
    }

    fn startThread(self: *App, ctx: *chasen.Ctx(Msg), visible_index: usize) !void {
        if (visible_index >= self.forums.thread_page.threads.len) return;
        const thread = self.forums.thread_page.threads[visible_index];
        self.thread.request_id +%= 1;
        self.browser.request_id +%= 1;
        const request_id = self.thread.request_id;

        self.thread.startLoad(self.allocator.?, thread.id, self.config.display.thread_width);
        self.thread.setVisibleHeight(threadLayoutForTerminal(self).content_height);
        self.switchScreenWithoutTransition(.thread);
        self.beginLoadingMotion(ctx);

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

    fn finishThread(self: *App, ctx: *chasen.Ctx(Msg), task_result: ThreadTaskResult) !void {
        if (task_result.request_id != self.thread.request_id) {
            switch (task_result.result) {
                .ok => |thread| bgg_xml.freeThread(self.allocator.?, thread),
                .failed => {},
            }
            return;
        }

        switch (task_result.result) {
            .ok => |thread| {
                try self.thread.setLoaded(self.allocator.?, thread);
                self.startContentTransitionIfVisible(ctx, .thread);
            },
            .failed => |message| self.thread.setFailed(message),
        }
    }

    fn backToThreadList(self: *App, ctx: *chasen.Ctx(Msg)) void {
        self.thread.request_id +%= 1;
        self.browser.request_id +%= 1;
        self.thread.deinit(self.allocator.?);
        self.enterPreparedScreen(.forums, ctx);
    }

    fn openThreadInBrowser(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        if (self.thread.load_state != .loaded or self.thread.thread_id == 0) return;

        const url = try formatOwnedText(ctx.allocator(), format.writeBggThreadUrl, .{self.thread.thread_id});
        errdefer ctx.allocator().free(url);

        self.browser.request_id +%= 1;
        const request_id = self.browser.request_id;

        const task = try ctx.allocator().create(BrowserOpenTask);
        errdefer ctx.allocator().destroy(task);
        task.* = .{ .url = url, .request_id = request_id, .target = .thread };

        ctx.spawnWith(task, BrowserOpenTask.run) catch |err| {
            ctx.allocator().free(url);
            return err;
        };
    }

    fn finishBrowserOpen(self: *App, task_result: BrowserOpenTaskResult) !void {
        if (task_result.request_id != self.browser.request_id) {
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

    fn handleResize(self: *App, size: chasen.Size) !void {
        self.terminal_size = size;
        if (self.screen == .game_detail) {
            self.game_detail.setVisibleHeight(detailLayoutForTerminal(self).content_height);
            try self.game_detail.rewrap(self.allocator.?, self.effectiveDetailContentWidth());
        }
        if (self.screen == .thread) {
            self.thread.setVisibleHeight(threadLayoutForTerminal(self).content_height);
        }
    }

    fn drawListPosition(self: *const App, surface: *chasen.Surface, list: *const ui.List) !void {
        try self.drawListPositionWithLegend(surface, list, "");
    }

    fn drawListPositionWithLegend(self: *const App, surface: *chasen.Surface, list: *const ui.List, legend: []const u8) !void {
        const item_count = list.items.len;
        if (item_count == 0 or surface.size().height < 2) return;

        const text = try list_view.focusedPositionText(surface.frameAllocator(), list.focusedIndex(), item_count);
        if (legend.len == 0) {
            _ = surface.borrowTextAt(0, list_position_row, text, self.subtleStyle());
        } else {
            _ = try surface.printAt(0, list_position_row, self.subtleStyle(), "{s} {s}", .{ text, legend });
        }
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
            if (focused) {
                motion.drawFocusedText(surface, 2, row, thread.subject, self.theme().focused, self.config.interface.selection, self.animation_frame);
            } else {
                _ = surface.borrowTextAt(2, row, thread.subject, .{});
            }

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
            _ = surface.borrowTextAt(content_col, row, marker, .{});
            if (index == focused_index) {
                motion.drawFocusedText(surface, content_col + 2, row, item, self.theme().focused, self.config.interface.selection, self.animation_frame);
            } else {
                _ = surface.borrowTextAt(content_col + 2, row, item, .{});
            }
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

    fn drawLoadingGuidance(self: *const App, surface: *chasen.Surface, row: u16, title: []const u8, message: []const u8) void {
        _ = surface.borrowTextAt(0, row, title, self.mutedTitleStyle());
        motion.drawStatusScanText(surface, 0, row + 1, message, self.mutedStyle(), self.loadingScanFrame());
    }

    fn drawCenteredGuidance(self: *const App, surface: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        const block = ui.MessageBlock.init(.{ .title = title, .message = message });
        block.view(surface, .{});
    }

    fn drawCenteredLoadingGuidance(self: *const App, surface: *chasen.Surface, title: []const u8, message: []const u8) void {
        const block = ui.MessageBlock.init(.{ .title = title, .message = message });
        block.view(surface, .{});
        if (block.layout(surface.size()).message) |point| {
            motion.drawStatusScanText(surface, point.col, point.row, message, self.mutedStyle(), self.loadingScanFrame());
        }
    }

    fn drawCenteredGuidanceKeepingCursor(self: *const App, surface: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        const block = ui.MessageBlock.init(.{ .title = title, .message = message });
        block.view(surface, .{ .hide_cursor = false });
    }

    fn drawSearchFilterInput(self: *const App, surface: *chasen.Surface) !void {
        _ = surface.borrowTextAt(0, list_filter_row, "Filter:", self.subtleStyle());
        if (self.search.filter_input) |*input| {
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
        if (self.collection.username_input) |*input| {
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
        if (self.collection.filter_input) |*input| {
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
        const text = collectionStatusSummary(surface.frameAllocator(), self.collection.status_mask) catch "Status: -";
        _ = surface.borrowTextAt(0, collection_status_bar_row, text, self.subtleStyle());
    }

    fn drawCollectionStatusPicker(self: *const App, surface: *chasen.Surface, start_row: u16) void {
        if (surface.size().height <= start_row) return;

        _ = surface.borrowTextAt(0, start_row, "Status Filter", self.mutedTitleStyle());
        for (collection_status_labels, 0..) |label, index| {
            const row: u16 = @intCast(start_row + 1 + index);
            if (row >= surface.size().height) return;
            const cursor = if (self.collection.status_cursor == index) "> " else "  ";
            const checked = if ((self.collection.status_mask & collectionStatusBit(index)) != 0) "[x]" else "[ ]";
            _ = surface.borrowTextAt(0, row, cursor, .{ .bold = self.collection.status_cursor == index });
            _ = surface.borrowTextAt(2, row, checked, .{ .fg = if ((self.collection.status_mask & collectionStatusBit(index)) != 0) self.theme().accent else .gray });
            _ = surface.borrowTextAt(6, row, label, .{});
        }

        const clear_row: u16 = @intCast(start_row + 1 + collection_picker_clear_index);
        if (clear_row < surface.size().height) {
            const cursor = if (self.collection.status_cursor == collection_picker_clear_index) "> " else "  ";
            _ = surface.borrowTextAt(0, clear_row, cursor, .{ .bold = self.collection.status_cursor == collection_picker_clear_index });
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

    fn requestMotionFrameIfNeeded(self: *const App, ctx: *chasen.Ctx(Msg)) void {
        if (motion.selectionNeedsFrame(self.config.interface.selection) or self.hasActiveLoadingScan() or self.hasActiveScreenTransition() or self.listImageCandidateWaiting()) {
            ctx.requestFrame();
        }
    }

    fn listImageCandidateWaiting(self: *const App) bool {
        return self.list_image.candidate != null and !self.list_image.candidateSettled(self.animation_frame);
    }

    fn enterPreparedScreen(self: *App, screen: Screen, ctx: *chasen.Ctx(Msg)) void {
        const previous_screen = self.screen;
        self.screen = screen;
        self.startScreenTransition(previous_screen, screen, ctx);
    }

    fn switchScreenWithoutTransition(self: *App, screen: Screen) void {
        self.screen = screen;
        self.clearScreenTransition();
    }

    fn startScreenTransition(self: *App, previous_screen: Screen, next_screen: Screen, ctx: *chasen.Ctx(Msg)) void {
        if (previous_screen == next_screen) {
            self.clearScreenTransition();
            return;
        }

        self.transition_choice_seed +|= 1;
        const kind = screenTransitionKindForConfig(self.config.interface.transition, transitionChoiceSeed(self.transition_choice_seed, self.animation_frame, previous_screen, next_screen));
        if (kind == .none) {
            self.clearScreenTransition();
            return;
        }

        self.transition_from_screen = previous_screen;
        self.transition_to_screen = next_screen;
        // Start at frame 1 so the first rendered frame reveals some content
        // instead of briefly clearing the entire screen.
        self.screen_transition = anim.Transition{
            .kind = kind,
            .frame = 1,
            .max_frame = screenTransitionFrames(kind),
        };
        self.requestMotionFrameIfNeeded(ctx);
    }

    fn startContentTransition(self: *App, ctx: *chasen.Ctx(Msg)) void {
        self.transition_choice_seed +|= 1;
        const kind = screenTransitionKindForConfig(self.config.interface.transition, transitionChoiceSeed(self.transition_choice_seed, self.animation_frame, self.screen, self.screen));
        if (kind == .none) {
            self.clearScreenTransition();
            return;
        }

        self.transition_from_screen = self.screen;
        self.transition_to_screen = self.screen;
        // Content transitions reveal newly loaded state inside the current
        // screen, so from/to intentionally point at the same screen.
        self.screen_transition = anim.Transition{
            .kind = kind,
            .frame = 1,
            .max_frame = screenTransitionFrames(kind),
        };
        self.requestMotionFrameIfNeeded(ctx);
    }

    fn startContentTransitionIfVisible(self: *App, ctx: *chasen.Ctx(Msg), target: Screen) void {
        if (self.screen != target) return;
        self.startContentTransition(ctx);
    }

    fn stepScreenTransition(self: *App) void {
        if (!self.hasActiveScreenTransition()) return;
        _ = self.screen_transition.step();
        if (self.screen_transition.done()) self.clearScreenTransition();
    }

    fn hasActiveScreenTransition(self: *const App) bool {
        return self.screen_transition.kind != .none and !self.screen_transition.done();
    }

    fn clearScreenTransition(self: *App) void {
        self.screen_transition = .{};
        self.transition_from_screen = null;
        self.transition_to_screen = null;
    }

    fn beginLoadingMotion(self: *App, ctx: *chasen.Ctx(Msg)) void {
        self.startLoadingScan();
        self.requestMotionFrameIfNeeded(ctx);
    }

    fn startLoadingScan(self: *App) void {
        self.loading_scan_start_frame = self.animation_frame;
    }

    fn loadingScanFrame(self: *const App) u64 {
        return self.animation_frame -| self.loading_scan_start_frame;
    }

    fn hasActiveLoadingScan(self: *const App) bool {
        return self.hot_games.load_state == .loading or
            self.search.load_state == .loading or
            self.collection.load_state == .loading or
            self.game_detail.load_state == .loading or
            self.forums.load_state == .loading_forums or
            self.forums.load_state == .loading_threads or
            self.thread.load_state == .loading;
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
                .loaded => if (self.collection.status_picker)
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

const HotGamesState = screens.hot_games.State;
const HotGamesMsg = screens.hot_games.Msg;
const HotGamesResult = screens.hot_games.Result;
const HotGameStatsResult = screens.hot_games.StatsResult;

const SetupTokenMsg = union(enum) {
    input: ui.PasswordInput.Msg,
    paste: []const u8,
};

const SearchState = struct {
    input: ?ui.TextInput = null,
    filter_input: ?ui.TextInput = null,
    request_id: u64 = 0,
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

    fn initInputs(self: *SearchState, allocator: std.mem.Allocator) !void {
        self.input = try ui.TextInput.init(allocator, .{
            .placeholder = "Search board games",
        });
        errdefer {
            self.input.?.deinit();
            self.input = null;
        }
        self.filter_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Filter search results",
        });
    }

    fn deinitInputs(self: *SearchState) void {
        if (self.input) |*input| {
            input.deinit();
            self.input = null;
        }
        if (self.filter_input) |*input| {
            input.deinit();
            self.filter_input = null;
        }
    }

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

const SearchResult = task_bgg.SearchResult;
const SearchTaskResult = task_bgg.SearchTaskResult;

const SearchMsg = union(enum) {
    input: ui.TextInput.Msg,
    paste: []const u8,
    filter_start,
    filter_input: ui.TextInput.Msg,
    filter_paste: []const u8,
    filter_clear,
    sort_toggle,
    results_loaded: SearchTaskResult,
    list: ui.List.Msg,
};

const CollectionState = struct {
    username_input: ?ui.TextInput = null,
    filter_input: ?ui.TextInput = null,
    request_id: u64 = 0,
    status_picker: bool = false,
    status_cursor: usize = 0,
    status_mask: u8 = 0,
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

    fn initInputs(self: *CollectionState, allocator: std.mem.Allocator, default_username: ?[]const u8) !void {
        self.username_input = try ui.TextInput.init(allocator, .{
            .value = default_username orelse "",
            .placeholder = "BGG username",
        });
        errdefer {
            self.username_input.?.deinit();
            self.username_input = null;
        }
        self.filter_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Filter collection",
        });
    }

    fn deinitInputs(self: *CollectionState) void {
        if (self.username_input) |*input| {
            input.deinit();
            self.username_input = null;
        }
        if (self.filter_input) |*input| {
            input.deinit();
            self.filter_input = null;
        }
    }

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

const CollectionResult = task_bgg.CollectionResult;
const CollectionTaskResult = task_bgg.CollectionTaskResult;

const CollectionMsg = union(enum) {
    username_input: ui.TextInput.Msg,
    username_paste: []const u8,
    filter_start,
    filter_input: ui.TextInput.Msg,
    filter_paste: []const u8,
    filter_clear,
    change_user,
    refresh,
    status_open,
    status_move_prev,
    status_move_next,
    status_toggle,
    status_close,
    items_loaded: CollectionTaskResult,
    list: ui.List.Msg,
};

const GameDetailResult = task_bgg.GameDetailResult;

const GameDetailImageResult = union(enum) {
    ok: []u8,
    failed: []const u8,
};

const GameDetailTaskResult = task_bgg.GameDetailTaskResult;

const GameDetailImageTaskResult = struct {
    request_id: u64,
    result: GameDetailImageResult,
};

const GameDetailTerminalImageLoadContext = struct {
    request_id: u64,
};

const GameDetailTerminalImageLoaded = struct {
    load_ctx: *GameDetailTerminalImageLoadContext,
    handle: chasen.TerminalImageHandle,
};

const GameDetailTerminalImageFailed = struct {
    load_ctx: *GameDetailTerminalImageLoadContext,
    reason: chasen.TerminalImageLoadError,
};

const ListImageResult = union(enum) {
    ok: []u8,
    failed: []const u8,
};

const ListImageTaskResult = struct {
    request_id: u64,
    result: ListImageResult,
};

const ListImageTerminalImageLoadContext = struct {
    request_id: u64,
};

const ListImageTerminalImageLoaded = struct {
    load_ctx: *ListImageTerminalImageLoadContext,
    handle: chasen.TerminalImageHandle,
};

const ListImageTerminalImageFailed = struct {
    load_ctx: *ListImageTerminalImageLoadContext,
    reason: chasen.TerminalImageLoadError,
};

const GameDetailMsg = union(enum) {
    loaded: GameDetailTaskResult,
    image_cached: GameDetailImageTaskResult,
    terminal_image_loaded: GameDetailTerminalImageLoaded,
    terminal_image_failed: GameDetailTerminalImageFailed,
    move_prev,
    move_next,
    open_browser,
};

const ListImageMsg = union(enum) {
    image_cached: ListImageTaskResult,
    terminal_image_loaded: ListImageTerminalImageLoaded,
    terminal_image_failed: ListImageTerminalImageFailed,
};

const ForumListResult = task_bgg.ForumListResult;
const ForumListTaskResult = task_bgg.ForumListTaskResult;
const ForumThreadsResult = task_bgg.ForumThreadsResult;
const ForumThreadsTaskResult = task_bgg.ForumThreadsTaskResult;

const ForumMsg = union(enum) {
    open,
    loaded: ForumListTaskResult,
    list: ui.List.Msg,
    threads_loaded: ForumThreadsTaskResult,
    thread_list: ui.List.Msg,
    back_to_detail,
    back_to_list,
    next_page,
    previous_page,
};

const ThreadResult = task_bgg.ThreadResult;
const ThreadTaskResult = task_bgg.ThreadTaskResult;

const ThreadMsg = union(enum) {
    loaded: ThreadTaskResult,
    move_prev,
    move_next,
    sort_toggle,
    open_browser,
    back_to_forums,
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

const BrowserMsg = union(enum) {
    opened: BrowserOpenTaskResult,
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

        return .{ .hot_games = .{ .loaded = task_bgg.loadHotGames(allocator, io, task.token) catch |err| .{ .failed = @errorName(err) } } };
    }
};

const HotGameStatsTask = struct {
    token: []const u8,
    ids: []u32,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *HotGameStatsTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.token);
            allocator.free(task.ids);
            allocator.destroy(task);
        }

        return .{ .hot_games = .{ .stats_loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadHotGameStats(allocator, io, task.token, task.ids) catch |err| .{ .failed = @errorName(err) },
        } } };
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

        return .{ .search = .{ .results_loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadSearchResults(allocator, io, task.token, task.query) catch |err| .{ .failed = @errorName(err) },
        } } };
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

        return .{ .collection = .{ .items_loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadCollectionItems(allocator, io, task.token, task.username) catch |err| .{ .failed = @errorName(err) },
        } } };
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

        return .{ .game_detail = .{ .loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadGameDetail(allocator, io, task.token, task.game_id) catch |err| .{ .failed = @errorName(err) },
        } } };
    }
};

const GameDetailImageTask = struct {
    cache_dir: []const u8,
    url: []const u8,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *GameDetailImageTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.cache_dir);
            allocator.free(task.url);
            allocator.destroy(task);
        }

        const cached = image_mod.downloadToCache(allocator, io, task.cache_dir, task.url) catch |err| {
            return .{ .game_detail = .{ .image_cached = .{
                .request_id = task.request_id,
                .result = .{ .failed = @errorName(err) },
            } } };
        };

        return .{ .game_detail = .{ .image_cached = .{
            .request_id = task.request_id,
            .result = .{ .ok = cached.path },
        } } };
    }
};

const ListImageTask = struct {
    cache_dir: []const u8,
    url: []const u8,
    request_id: u64,

    fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, io: std.Io) App.Msg {
        const task: *ListImageTask = @ptrCast(@alignCast(ctx_ptr));
        defer {
            allocator.free(task.cache_dir);
            allocator.free(task.url);
            allocator.destroy(task);
        }

        const cached = image_mod.downloadToCache(allocator, io, task.cache_dir, task.url) catch |err| {
            return .{ .list_image = .{ .image_cached = .{
                .request_id = task.request_id,
                .result = .{ .failed = @errorName(err) },
            } } };
        };

        return .{ .list_image = .{ .image_cached = .{
            .request_id = task.request_id,
            .result = .{ .ok = cached.path },
        } } };
    }
};

fn gameDetailTerminalImageLoaded(ctx_ptr: *anyopaque, handle: chasen.TerminalImageHandle) App.Msg {
    const load_ctx: *GameDetailTerminalImageLoadContext = @ptrCast(@alignCast(ctx_ptr));
    return .{ .game_detail = .{ .terminal_image_loaded = .{
        .load_ctx = load_ctx,
        .handle = handle,
    } } };
}

fn gameDetailTerminalImageFailed(ctx_ptr: *anyopaque, reason: chasen.TerminalImageLoadError) App.Msg {
    const load_ctx: *GameDetailTerminalImageLoadContext = @ptrCast(@alignCast(ctx_ptr));
    return .{ .game_detail = .{ .terminal_image_failed = .{
        .load_ctx = load_ctx,
        .reason = reason,
    } } };
}

fn listImageTerminalImageLoaded(ctx_ptr: *anyopaque, handle: chasen.TerminalImageHandle) App.Msg {
    const load_ctx: *ListImageTerminalImageLoadContext = @ptrCast(@alignCast(ctx_ptr));
    return .{ .list_image = .{ .terminal_image_loaded = .{
        .load_ctx = load_ctx,
        .handle = handle,
    } } };
}

fn listImageTerminalImageFailed(ctx_ptr: *anyopaque, reason: chasen.TerminalImageLoadError) App.Msg {
    const load_ctx: *ListImageTerminalImageLoadContext = @ptrCast(@alignCast(ctx_ptr));
    return .{ .list_image = .{ .terminal_image_failed = .{
        .load_ctx = load_ctx,
        .reason = reason,
    } } };
}

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

        return .{ .forum = .{ .loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadForumList(allocator, io, task.token, task.game_id) catch |err| .{ .failed = @errorName(err) },
        } } };
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

        return .{ .forum = .{ .threads_loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadForumThreads(allocator, io, task.token, task.forum_id, task.page) catch |err| .{ .failed = @errorName(err) },
        } } };
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

        return .{ .thread = .{ .loaded = .{
            .request_id = task.request_id,
            .result = task_bgg.loadThread(allocator, io, task.token, task.thread_id) catch |err| .{ .failed = @errorName(err) },
        } } };
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
            return .{ .browser = .{ .opened = .{
                .request_id = task.request_id,
                .target = task.target,
                .result = .{ .failed = task.url },
            } } };
        };
        allocator.free(task.url);
        return .{ .browser = .{ .opened = .{
            .request_id = task.request_id,
            .target = task.target,
            .result = .ok,
        } } };
    }
};

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

fn isListImageScreen(screen: Screen) bool {
    return switch (screen) {
        .hot_games, .collection => true,
        else => false,
    };
}

fn detailImageLoadErrorText(reason: chasen.TerminalImageLoadError) []const u8 {
    return switch (reason) {
        .unsupported => "Images unsupported",
        .load_failed => "Could not load image",
        .registry_full => "Image registry full",
    };
}

fn detailUnsupportedImageFormatText(format_kind: image_mod.SourceFormat) []const u8 {
    return switch (format_kind) {
        .jpeg => "JPEG covers not supported yet",
        .webp => "WebP covers not supported yet",
        .unknown => "Cover format not supported",
        .png => "Could not load image",
    };
}

fn listImagePanelMessage(message: []const u8) []const u8 {
    if (std.mem.eql(u8, message, "JPEG covers not supported yet")) return "JPEG not supported";
    if (std.mem.eql(u8, message, "WebP covers not supported yet")) return "WebP not supported";
    if (std.mem.eql(u8, message, "Cover format not supported")) return "Unsupported format";
    return message;
}

fn threadLayoutForTerminal(self: *const App) screens.thread.Layout {
    return layout_mod.threadLayout(layout_mod.screenBodySizeForTerminal(self.terminal_size).height, self.config.interface.list_density);
}

fn detailLayoutForTerminal(self: *const App) screens.detail.Layout {
    return layout_mod.detailLayout(layout_mod.screenBodySizeForTerminal(self.terminal_size).height, self.config.interface.list_density);
}

fn freePendingHotGameStatsTasks(ctx: *chasen.Ctx(App.Msg)) void {
    for (ctx.pendingTaskWithSlice()) |entry| {
        const task: *HotGameStatsTask = @ptrCast(@alignCast(entry.ctx));
        ctx.allocator().free(task.token);
        ctx.allocator().free(task.ids);
        ctx.allocator().destroy(task);
    }
    ctx.pending_tasks_with_len = 0;
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

fn screenTransitionKind(value: []const u8) anim.TransitionKind {
    return transitions.kindForValue(value);
}

fn screenTransitionKindForConfig(value: []const u8, seed: u64) anim.TransitionKind {
    return transitions.kindForConfig(value, seed);
}

fn randomScreenTransitionKind(seed: u64) anim.TransitionKind {
    return transitions.randomKind(seed);
}

fn transitionChoiceSeed(counter: u64, frame: u64, previous_screen: Screen, next_screen: Screen) u64 {
    return counter ^ (frame *% 0x9e37_79b9_7f4a_7c15) ^
        (@as(u64, @intCast(@intFromEnum(previous_screen))) *% 0xbf58_476d_1ce4_e5b9) ^
        (@as(u64, @intCast(@intFromEnum(next_screen))) *% 0x94d0_49bb_1331_11eb);
}

fn screenTransitionFrames(kind: anim.TransitionKind) u64 {
    return transitions.framesForKind(kind);
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
    try paste.insertCodepoints(input, text);
}

fn parseSettingsWidth(text: []const u8) !u16 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const value = try std.fmt.parseInt(u16, trimmed, 10);
    if (value < 20 or value > 240) return error.InvalidWidth;
    return value;
}

const color_theme_values = [_][]const u8{ "default", "blue", "orange", "mono", "matcha" };
const transition_values = transitions.values;
const selection_values = [_][]const u8{ "none", "invert", "wave", "blink", "glitch", "scan" };
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
    const body_size = layout_mod.screenBodySizeForTerminal(.{ .width = 80, .height = 10 });

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

test "screen transition kind only enables implemented effects" {
    try std.testing.expectEqual(anim.TransitionKind.none, screenTransitionKind("none"));
    try std.testing.expectEqual(anim.TransitionKind.code_rain, screenTransitionKind("code-rain"));
    try std.testing.expectEqual(anim.TransitionKind.dissolve, screenTransitionKind("dissolve"));
    try std.testing.expectEqual(anim.TransitionKind.fade, screenTransitionKind("fade"));
    try std.testing.expectEqual(anim.TransitionKind.glitch, screenTransitionKind("glitch"));
    try std.testing.expectEqual(anim.TransitionKind.iris, screenTransitionKind("iris"));
    try std.testing.expectEqual(anim.TransitionKind.lines, screenTransitionKind("lines"));
    try std.testing.expectEqual(anim.TransitionKind.lines_cross, screenTransitionKind("lines-cross"));
    try std.testing.expectEqual(anim.TransitionKind.scanline, screenTransitionKind("scanline"));
    try std.testing.expectEqual(anim.TransitionKind.shutter, screenTransitionKind("shutter"));
    try std.testing.expectEqual(anim.TransitionKind.spiral, screenTransitionKind("spiral"));
    try std.testing.expectEqual(anim.TransitionKind.sweep, screenTransitionKind("sweep"));
    try std.testing.expectEqual(anim.TransitionKind.warp, screenTransitionKind("warp"));
    try std.testing.expectEqual(anim.TransitionKind.none, screenTransitionKind("wipe"));
    try std.testing.expectEqual(anim.TransitionKind.none, screenTransitionKind("random"));
}

test "random screen transition resolves to implemented effects" {
    var saw_fade = false;
    var saw_glitch = false;
    var saw_code_rain = false;
    var saw_dissolve = false;
    var saw_sweep = false;
    var saw_spiral = false;
    var saw_warp = false;
    var saw_scanline = false;
    var saw_iris = false;
    var saw_shutter = false;
    var saw_lines = false;
    var saw_lines_cross = false;

    var seed: u64 = 0;
    while (seed < 512) : (seed += 1) {
        switch (screenTransitionKindForConfig("random", seed)) {
            .fade => saw_fade = true,
            .glitch => saw_glitch = true,
            .code_rain => saw_code_rain = true,
            .dissolve => saw_dissolve = true,
            .sweep => saw_sweep = true,
            .spiral => saw_spiral = true,
            .warp => saw_warp = true,
            .scanline => saw_scanline = true,
            .iris => saw_iris = true,
            .shutter => saw_shutter = true,
            .lines => saw_lines = true,
            .lines_cross => saw_lines_cross = true,
            else => return error.UnexpectedTransitionKind,
        }
    }

    try std.testing.expect(saw_fade);
    try std.testing.expect(saw_glitch);
    try std.testing.expect(saw_code_rain);
    try std.testing.expect(saw_dissolve);
    try std.testing.expect(saw_sweep);
    try std.testing.expect(saw_spiral);
    try std.testing.expect(saw_warp);
    try std.testing.expect(saw_scanline);
    try std.testing.expect(saw_iris);
    try std.testing.expect(saw_shutter);
    try std.testing.expect(saw_lines);
    try std.testing.expect(saw_lines_cross);
}

test "screen transition frame counts can differ by effect" {
    try std.testing.expectEqual(@as(u64, 84), screenTransitionFrames(.sweep));
    try std.testing.expectEqual(@as(u64, 84), screenTransitionFrames(.fade));
    try std.testing.expectEqual(@as(u64, 96), screenTransitionFrames(.code_rain));
    try std.testing.expectEqual(@as(u64, 60), screenTransitionFrames(.dissolve));
    try std.testing.expectEqual(@as(u64, 192), screenTransitionFrames(.glitch));
    try std.testing.expectEqual(@as(u64, 90), screenTransitionFrames(.iris));
    try std.testing.expectEqual(@as(u64, 90), screenTransitionFrames(.lines));
    try std.testing.expectEqual(@as(u64, 90), screenTransitionFrames(.lines_cross));
    try std.testing.expectEqual(@as(u64, 110), screenTransitionFrames(.scanline));
    try std.testing.expectEqual(@as(u64, 72), screenTransitionFrames(.shutter));
    try std.testing.expectEqual(@as(u64, 104), screenTransitionFrames(.spiral));
    try std.testing.expectEqual(@as(u64, 96), screenTransitionFrames(.warp));
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
    app.collection.status_picker = true;
    try std.testing.expectEqualStrings("Up/Down: move  Enter: toggle  Esc: close", app.footerHint());
    app.collection.status_picker = false;
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

    try paste.insertCodepoints(&input, " tok-123\n\tあ ");

    try std.testing.expectEqualStrings(" tok-123あ ", input.text());
}

test "setup token screen maps paste to paste message" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    app.setup_token_input = try ui.PasswordInput.init(std.testing.allocator, .{});
    defer app.deinitOwnedState();

    const msg = app.handleEvent(.{ .paste = "token" }).?;
    try std.testing.expect(msg == .setup_token);
    try std.testing.expectEqualStrings("token", msg.setup_token.paste);
}

test "search paste inserts printable query text" {
    var input = try ui.TextInput.init(std.testing.allocator, .{});
    defer input.deinit();

    try paste.insertCodepoints(&input, "Catan\n\tDuel");

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

    try std.testing.expectEqualStrings("hiro", app.collection.username_input.?.text());
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
    app.search.input = try ui.TextInput.init(std.testing.allocator, .{ .value = "go" });
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startSearch(&tc.ctx);

    try std.testing.expect(app.search.load_state == .failed);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "collection empty username fails before spawning task" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.collection.username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "  " });
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

    try std.testing.expectEqual(collectionStatusBit(6), app.collection.status_mask);
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
    app.search.input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    try app.search.setLoaded(std.testing.allocator, results);
    app.search.request_id = 7;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.showScreen(.search, &tc.ctx);

    try std.testing.expectEqual(Screen.search, app.screen);
    try std.testing.expectEqualStrings("", app.search.input.?.text());
    try std.testing.expect(app.search.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.search.results.len);
    try std.testing.expectEqual(@as(u64, 8), app.search.request_id);
}

test "showing search from search results preserves previous query and results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .search_results;
    app.search.input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };
    try app.search.setLoaded(std.testing.allocator, results);
    app.search.request_id = 7;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.showScreen(.search, &tc.ctx);

    try std.testing.expectEqual(Screen.search, app.screen);
    try std.testing.expectEqualStrings("root", app.search.input.?.text());
    try std.testing.expect(app.search.load_state == .loaded);
    try std.testing.expectEqual(@as(usize, 1), app.search.results.len);
    try std.testing.expectEqual(@as(u64, 7), app.search.request_id);
}

test "loaded search results receive activation on search results screen" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .search_results;
    app.search.input = try ui.TextInput.init(std.testing.allocator, .{ .value = "root" });
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    try app.search.setLoaded(std.testing.allocator, results);

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.enter } }).?;
    try std.testing.expect(msg == .search);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 0 }, msg.search.list);
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
    try std.testing.expect(msg == .collection);
    try std.testing.expectEqual(ui.List.Msg{ .activate = 0 }, msg.collection.list);
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
    try std.testing.expect(msg == .collection);
    try std.testing.expect(msg.collection == .filter_start);
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
    try std.testing.expect(user_msg == .collection);
    try std.testing.expect(user_msg.collection == .change_user);

    const refresh_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'r' } }).?;
    try std.testing.expect(refresh_msg == .collection);
    try std.testing.expect(refresh_msg.collection == .refresh);
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
    try std.testing.expect(msg == .collection);
    try std.testing.expect(msg.collection == .status_open);
}

test "collection status picker toggles multiple statuses without request" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 3);
    items[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Owned"), .owned = true };
    items[1] = .{ .id = 2, .name = try std.testing.allocator.dupe(u8, "Wishlist"), .wishlist = true };
    items[2] = .{ .id = 3, .name = try std.testing.allocator.dupe(u8, "Both"), .owned = true, .wishlist = true };
    app.collection.status_mask = collectionStatusBit(0);
    try app.collection.setLoaded(std.testing.allocator, items, collectionStatusBit(0));

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.openCollectionStatusPicker();
    app.collection.status_cursor = 6;
    try app.toggleCollectionStatus(&tc.ctx);

    try std.testing.expectEqual(collectionStatusBit(0) | collectionStatusBit(6), app.collection.status_mask);
    try std.testing.expectEqual(collectionStatusBit(0) | collectionStatusBit(6), app.config.collection.status_filter.mask);
    try std.testing.expectEqual(@as(usize, 3), app.collection.items.len);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);

    app.collection.status_cursor = collection_picker_clear_index;
    try app.toggleCollectionStatus(&tc.ctx);

    try std.testing.expectEqual(@as(u8, 0), app.collection.status_mask);
    try std.testing.expectEqual(@as(u8, 0), app.config.collection.status_filter.mask);
    try std.testing.expectEqual(@as(usize, 3), app.collection.items.len);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "changing collection user clears loaded state and invalidates tasks" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.collection.filter_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "ca" });
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN") };
    try app.collection.setLoaded(std.testing.allocator, items, 0);
    try app.collection.applyFilter(std.testing.allocator, "cat");
    app.collection.request_id = 7;

    try app.changeCollectionUser();

    try std.testing.expect(app.collection.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.collection.items.len);
    try std.testing.expect(!app.collection.filter_active);
    try std.testing.expectEqualStrings("", app.collection.filter_input.?.text());
    try std.testing.expectEqual(@as(u64, 8), app.collection.request_id);
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
    app.navigation.detail_back_screen = .search_results;

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
    try std.testing.expect(msg == .forum);
    try std.testing.expect(msg.forum == .open);
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
    try std.testing.expect(msg == .game_detail);
    try std.testing.expect(msg.game_detail == .open_browser);
}

test "forum back key returns to detail or forum list" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.screen = .forums;
    app.forums.mode = .forum_list;
    const detail_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'b' } }).?;
    try std.testing.expect(detail_msg == .forum);
    try std.testing.expect(detail_msg.forum == .back_to_detail);

    app.forums.mode = .thread_list;
    const list_msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'b' } }).?;
    try std.testing.expect(list_msg == .forum);
    try std.testing.expect(list_msg.forum == .back_to_list);
}

test "forum back to list invalidates in-flight thread load" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.forums.thread_list_request_id = 7;
    app.forums.mode = .thread_list;
    app.backToForumList();
    try std.testing.expectEqual(@as(u64, 8), app.forums.thread_list_request_id);
    try std.testing.expectEqual(screens.forum.Mode.forum_list, app.forums.mode);

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Old response"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };
    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.finishForumThreads(&tc.ctx, .{
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
    try app.handleResize(.{ .width = 80, .height = 10 });
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
    try app.handleResize(.{ .width = 80, .height = 10 });
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
    for (0..10) |_| try app.update(.{ .game_detail = .move_next }, &tc.ctx);
    try std.testing.expectEqual(app.game_detail.maxScroll(detailLayoutForTerminal(&app).content_height), app.game_detail.scroll);
}

test "loaded thread o opens browser" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .thread;
    app.thread.thread_id = 100;
    app.thread.load_state = .loaded;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = 'o' } }).?;
    try std.testing.expect(msg == .thread);
    try std.testing.expect(msg.thread == .open_browser);
}

test "stale browser failure does not update current thread" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.browser.request_id = 2;
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

    app.browser.request_id = 7;
    const next_thread = app.forums.thread_page.threads[0];
    app.thread.request_id +%= 1;
    app.browser.request_id +%= 1;
    app.thread.startLoad(std.testing.allocator, next_thread.id, app.config.display.thread_width);
    app.screen = .thread;
    try std.testing.expectEqual(@as(u64, 8), app.browser.request_id);

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
    app.settings.token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "  new-token  " });
    app.settings.startEdit(.token);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsToken(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("new-token", app.config.apiClientToken().?);
    try std.testing.expectEqualStrings("", app.settings.token_input.?.text());
}

test "settings token edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-token/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings.token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "settings-token" });
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
    app.settings.token_input = try ui.PasswordInput.init(std.testing.allocator, .{ .value = "new-token" });
    app.settings.startEdit(.token);
    defer app.deinitOwnedState();

    app.cancelSettingsTokenEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("old-token", app.config.apiClientToken().?);
    try std.testing.expectEqualStrings("", app.settings.token_input.?.text());
}

test "settings username edit saves username and stays on settings" {
    var app = App.create(.{ .collection = .{ .default_username = "old-user" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .settings;
    app.settings.username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "  new-user  " });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsUsername(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("new-user", app.config.collection.default_username.?);
    try std.testing.expectEqualStrings("", app.settings.username_input.?.text());
}

test "settings username edit clears username when empty" {
    var app = App.create(.{ .collection = .{ .default_username = "old-user" } }, .{});
    app.allocator = std.testing.allocator;
    app.settings.username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "   " });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsUsername(&tc.ctx);

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expect(app.config.collection.default_username == null);
    try std.testing.expectEqualStrings("", app.settings.username_input.?.text());
}

test "settings username edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-username/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings.username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "hiro" });
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
    app.settings.username_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "new-user" });
    app.settings.startEdit(.username);
    defer app.deinitOwnedState();

    app.cancelSettingsUsernameEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqualStrings("old-user", app.config.collection.default_username.?);
    try std.testing.expectEqualStrings("", app.settings.username_input.?.text());
}

test "settings width edit saves selected width and stays on settings" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    app.screen = .settings;
    app.settings.width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "120" });
    app.settings.startEdit(.thread_width);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsWidth(&tc.ctx);

    try std.testing.expectEqual(Screen.settings, app.screen);
    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqual(@as(u16, 120), app.config.display.thread_width);
    try std.testing.expectEqualStrings("", app.settings.width_input.?.text());
}

test "settings width edit ignores invalid width" {
    var app = App.create(.{ .display = .{ .list_width = 40 } }, .{});
    app.allocator = std.testing.allocator;
    app.settings.width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "10" });
    app.settings.startEdit(.list_width);
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.submitSettingsWidth(&tc.ctx);

    try std.testing.expectEqual(@as(u16, 40), app.config.display.list_width);
    try std.testing.expectEqual(screens.settings.EditField.list_width, app.settings.editing.?);
    try std.testing.expectEqualStrings("10", app.settings.width_input.?.text());
}

test "settings width edit saves config when path is available" {
    const path = ".zig-cache/test-bgg-tui-settings-width/config.toml";

    var app = App.create(.{}, .{ .config_path = path });
    app.allocator = std.testing.allocator;
    app.settings.width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "144" });
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
    app.settings.width_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "120" });
    app.settings.startEdit(.detail_width);
    defer app.deinitOwnedState();

    app.cancelSettingsWidthEdit();

    try std.testing.expect(app.settings.editing == null);
    try std.testing.expectEqual(@as(u16, 90), app.config.display.detail_width);
    try std.testing.expectEqualStrings("", app.settings.width_input.?.text());
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
    tc.resetTransient();
    try app.cycleSettingsField(&tc.ctx, .transition);
    try std.testing.expectEqualStrings("fade", app.config.interface.transition);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.setup_token, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.setup_token, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
    try app.cycleSettingsField(&tc.ctx, .selection);
    try std.testing.expectEqualStrings("invert", app.config.interface.selection);
    try app.cycleSettingsField(&tc.ctx, .border_style);
    try std.testing.expectEqualStrings("thick", app.config.interface.border_style);
    try app.cycleSettingsField(&tc.ctx, .list_density);
    try std.testing.expectEqualStrings("comfortable", app.config.interface.list_density);
    try app.cycleSettingsField(&tc.ctx, .date_format);
    try std.testing.expectEqualStrings("yyyy/mm/dd", app.config.interface.date_format);
}

test "animated selection requests animation frames" {
    var app = App.create(.{ .interface = .{ .selection = "wave" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try std.testing.expect(tc.ctx.frame_requested);

    tc.resetTransient();
    try app.update(.{ .frame = .{ .now_ns = 100, .delta_ns = 16, .index = 15 } }, &tc.ctx);
    try std.testing.expectEqual(@as(u64, 15), app.animation_frame);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "non-animated selection does not request animation frames" {
    var app = App.create(.{}, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try std.testing.expect(!tc.ctx.frame_requested);
}

test "none screen transition uses routing path without requesting frames" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "none" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    tc.resetTransient();
    try app.showScreen(.search, &tc.ctx);

    try std.testing.expectEqual(Screen.search, app.screen);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "sweep screen transition requests frames until completion" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    tc.resetTransient();
    try app.showScreen(.settings, &tc.ctx);

    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(anim.TransitionKind.sweep, app.screen_transition.kind);
    try std.testing.expectEqual(Screen.main_menu, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.settings, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);

    var frame_index: u64 = 1;
    while (app.hasActiveScreenTransition()) : (frame_index += 1) {
        tc.resetTransient();
        try app.update(.{ .frame = .{ .now_ns = frame_index * 16, .delta_ns = 16, .index = frame_index } }, &tc.ctx);
    }

    try std.testing.expectEqual(anim.TransitionKind.none, app.screen_transition.kind);
    try std.testing.expect(app.transition_from_screen == null);
    try std.testing.expect(app.transition_to_screen == null);
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "prepared screen entry keeps target state before transition starts" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.search.setLoading(std.testing.allocator);
    app.enterPreparedScreen(.search_results, &tc.ctx);

    try std.testing.expectEqual(Screen.search_results, app.screen);
    try std.testing.expect(app.search.load_state == .loading);
    try std.testing.expect(app.hasActiveScreenTransition());
}

test "screen switch without transition clears active transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    app.switchScreenWithoutTransition(.search_results);

    try std.testing.expectEqual(Screen.search_results, app.screen);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(app.transition_from_screen == null);
    try std.testing.expect(app.transition_to_screen == null);
}

test "content transition can start within the current screen" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    app.screen = .game_detail;
    tc.resetTransient();
    app.startContentTransition(&tc.ctx);

    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(anim.TransitionKind.sweep, app.screen_transition.kind);
    try std.testing.expectEqual(Screen.game_detail, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.game_detail, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "content transition only starts when target screen is visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    app.screen = .main_menu;
    tc.resetTransient();
    app.startContentTransitionIfVisible(&tc.ctx, .game_detail);

    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);

    app.screen = .game_detail;
    app.startContentTransitionIfVisible(&tc.ctx, .game_detail);

    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.game_detail, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.game_detail, app.transition_to_screen.?);
}

test "game detail loading enters without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    tc.resetTransient();
    try app.startGameDetail(&tc.ctx, 13, .hot_games);
    defer {
        const task: *GameDetailTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.game_detail, app.screen);
    try std.testing.expect(app.game_detail.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "game detail load completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "Catan") };

    app.screen = .game_detail;
    app.game_detail.request_id = 7;
    tc.resetTransient();
    try app.finishGameDetail(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = games } });

    try std.testing.expect(app.game_detail.load_state == .loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.game_detail, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.game_detail, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "game detail load completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "Catan") };

    app.screen = .main_menu;
    app.game_detail.request_id = 7;
    tc.resetTransient();
    try app.finishGameDetail(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = games } });

    try std.testing.expect(app.game_detail.load_state == .loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "game detail image url prefers full image over thumbnail" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.jpg"),
        .image_url = try std.testing.allocator.dupe(u8, "https://example.test/full.jpg"),
    };

    try app.game_detail.setLoaded(std.testing.allocator, games, app.config.display.detail_width);

    try std.testing.expectEqualStrings("https://example.test/full.jpg", app.gameDetailImageUrl().?);
}

test "game detail image url falls back to thumbnail" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.jpg"),
    };

    try app.game_detail.setLoaded(std.testing.allocator, games, app.config.display.detail_width);

    try std.testing.expectEqualStrings("https://example.test/thumb.jpg", app.gameDetailImageUrl().?);
}

test "game detail skips unsupported cover formats before cache task" {
    var app = App.create(.{}, .{ .image_cache_dir = "/tmp/bgg-tui-images" });
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .image_url = try std.testing.allocator.dupe(u8, "https://example.test/full.jpg"),
    };

    try app.game_detail.setLoaded(std.testing.allocator, games, app.config.display.detail_width);

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startGameDetailImageCache(&tc.ctx);

    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTaskWithSlice().len);
    switch (app.game_detail.image_state) {
        .failed => |message| try std.testing.expectEqualStrings("JPEG covers not supported yet", message),
        else => return error.TestExpectedEqual,
    }
}

test "hot list image preview reports unsupported JPEG thumbnail without cache task" {
    var app = App.create(.{}, .{ .image_cache_dir = "/tmp/bgg-tui-images" });
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{
        .id = 13,
        .rank = 1,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.jpg"),
    };
    try app.hot_games.setLoaded(std.testing.allocator, games);

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.syncListImagePreview(&tc.ctx);

    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTaskWithSlice().len);
    switch (app.list_image.image_state) {
        .failed => |message| try std.testing.expectEqualStrings("JPEG covers not supported yet", message),
        else => return error.TestExpectedEqual,
    }
}

test "hot list image preview waits before uncached PNG download" {
    var app = App.create(.{}, .{ .image_cache_dir = ".zig-cache/test-bgg-tui-list-image" });
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{
        .id = 13,
        .rank = 1,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.png"),
    };
    try app.hot_games.setLoaded(std.testing.allocator, games);

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.syncListImagePreview(&tc.ctx);
    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTaskWithSlice().len);

    try app.update(.{ .frame = .{ .now_ns = 16, .delta_ns = 16, .index = list_image_focus_settle_frames } }, &tc.ctx);
    defer {
        for (tc.ctx.pendingTaskWithSlice()) |entry| {
            const task: *ListImageTask = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.free(task.cache_dir);
            std.testing.allocator.free(task.url);
            std.testing.allocator.destroy(task);
        }
        tc.ctx.pending_tasks_with_len = 0;
    }

    try std.testing.expectEqual(@as(usize, 1), tc.ctx.pendingTaskWithSlice().len);
}

test "hot list image preview retries cached terminal load after transition" {
    var app = App.create(.{ .interface = .{ .transition = "sweep" } }, .{ .image_cache_dir = ".zig-cache/test-bgg-tui-list-image-cached" });
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{
        .id = 13,
        .rank = 1,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.png"),
    };
    try app.hot_games.setLoaded(std.testing.allocator, games);

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };

    const cached_path = try image_mod.cachePathForUrl(std.testing.allocator, app.image_cache_dir.?, games[0].thumbnail_url.?);
    defer std.testing.allocator.free(cached_path);
    if (std.fs.path.dirname(cached_path)) |parent| try std.Io.Dir.cwd().createDirPath(std.testing.io, parent);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = cached_path, .data = "png" });

    app.startContentTransition(&tc.ctx);
    try app.syncListImagePreview(&tc.ctx);
    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTerminalImageLoadSlice().len);

    var frame_index: u64 = 1;
    while (app.hasActiveScreenTransition()) : (frame_index += 1) {
        try app.update(.{ .frame = .{ .now_ns = frame_index * 16, .delta_ns = 16, .index = frame_index } }, &tc.ctx);
    }
    defer {
        for (tc.ctx.pendingTerminalImageLoadSlice()) |entry| {
            std.testing.allocator.free(entry.path);
            const load_ctx: *ListImageTerminalImageLoadContext = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.destroy(load_ctx);
        }
        tc.ctx.pending_terminal_image_loads_len = 0;
    }

    try std.testing.expectEqual(@as(usize, 1), tc.ctx.pendingTerminalImageLoadSlice().len);
}

test "collection list image preview reports unsupported JPEG thumbnail without cache task" {
    var app = App.create(.{}, .{ .image_cache_dir = "/tmp/bgg-tui-images" });
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.jpg"),
        .owned = true,
    };
    try app.collection.setLoaded(std.testing.allocator, items, 0);

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.syncListImagePreview(&tc.ctx);

    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTaskWithSlice().len);
    switch (app.list_image.image_state) {
        .failed => |message| try std.testing.expectEqualStrings("JPEG covers not supported yet", message),
        else => return error.TestExpectedEqual,
    }
}

test "collection list image preview waits before uncached PNG download" {
    var app = App.create(.{}, .{ .image_cache_dir = ".zig-cache/test-bgg-tui-collection-list-image" });
    app.allocator = std.testing.allocator;
    app.screen = .collection;
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{
        .id = 13,
        .name = try std.testing.allocator.dupe(u8, "Catan"),
        .thumbnail_url = try std.testing.allocator.dupe(u8, "https://example.test/thumb.png"),
        .owned = true,
    };
    try app.collection.setLoaded(std.testing.allocator, items, 0);

    var tc: chasen.testing.TestCtx(App.Msg) = .{
        .ctx = .{ ._allocator = std.testing.allocator, ._io = std.testing.io },
    };
    try app.syncListImagePreview(&tc.ctx);
    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTaskWithSlice().len);

    try app.update(.{ .frame = .{ .now_ns = 16, .delta_ns = 16, .index = list_image_focus_settle_frames } }, &tc.ctx);
    defer {
        for (tc.ctx.pendingTaskWithSlice()) |entry| {
            const task: *ListImageTask = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.free(task.cache_dir);
            std.testing.allocator.free(task.url);
            std.testing.allocator.destroy(task);
        }
        tc.ctx.pending_tasks_with_len = 0;
    }

    try std.testing.expectEqual(@as(usize, 1), tc.ctx.pendingTaskWithSlice().len);
}

test "collection list image panel avoids status picker area" {
    const config: config_mod.Config = .{};
    const compact_size = chasen.Size{ .width = layout_mod.list_image_min_text_width + list_image_panel_gap + layout_mod.list_image_panel_width, .height = 20 };
    const compact_picker_row = @max(collection_body_row, compact_size.height -| (collection_status_picker_lines + 1));
    try std.testing.expectEqual(@as(?chasen.Rect, null), layout_mod.listImagePanelRectForSize(config, compact_size, collection_body_row, compact_picker_row));

    const roomy_size = chasen.Size{ .width = layout_mod.list_image_min_text_width + list_image_panel_gap + layout_mod.list_image_panel_width, .height = 34 };
    const roomy_picker_row = @max(collection_body_row, roomy_size.height -| (collection_status_picker_lines + 1));
    const rect = layout_mod.listImagePanelRectForSize(config, roomy_size, collection_body_row, roomy_picker_row).?;
    try std.testing.expect(rect.row + rect.height < roomy_picker_row);
}

test "stale game detail image cache result is ignored" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.game_detail.image_request_id = 2;
    const stale_path = try std.testing.allocator.dupe(u8, "/tmp/stale-cover.png");
    var tc: chasen.testing.TestCtx(App.Msg) = .{};

    try app.finishGameDetailImageCache(&tc.ctx, .{
        .request_id = 1,
        .result = .{ .ok = stale_path },
    });

    try std.testing.expect(app.game_detail.image_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTerminalImageLoadSlice().len);
}

test "starting a new game detail invalidates in-flight image cache results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    app.game_detail.image_request_id = 4;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startGameDetail(&tc.ctx, 13, .hot_games);
    defer {
        const task: *GameDetailTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    const stale_path = try std.testing.allocator.dupe(u8, "/tmp/stale-cover.png");
    try app.finishGameDetailImageCache(&tc.ctx, .{
        .request_id = 4,
        .result = .{ .ok = stale_path },
    });

    try std.testing.expect(app.game_detail.image_state == .idle);
}

test "game detail cached image queues terminal image load" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.screen = .game_detail;
    app.game_detail.image_request_id = 3;
    const cached_path = try std.testing.allocator.dupe(u8, "/tmp/cover.png");

    try app.finishGameDetailImageCache(&tc.ctx, .{
        .request_id = 3,
        .result = .{ .ok = cached_path },
    });
    defer {
        for (tc.ctx.pendingTerminalImageLoadSlice()) |entry| {
            std.testing.allocator.free(entry.path);
            const load_ctx: *GameDetailTerminalImageLoadContext = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.destroy(load_ctx);
        }
        tc.ctx.pending_terminal_image_loads_len = 0;
    }

    const pending = tc.ctx.pendingTerminalImageLoadSlice();
    try std.testing.expectEqual(@as(usize, 1), pending.len);
    try std.testing.expectEqualStrings("/tmp/cover.png", pending[0].path);
    try std.testing.expect(app.game_detail.image_state == .cached);
}

test "game detail terminal image load waits for transition completion" {
    var app = App.create(.{ .interface = .{ .transition = "sweep" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.screen = .game_detail;
    app.game_detail.image_request_id = 3;
    app.startContentTransition(&tc.ctx);

    const cached_path = try std.testing.allocator.dupe(u8, "/tmp/cover.png");
    try app.finishGameDetailImageCache(&tc.ctx, .{
        .request_id = 3,
        .result = .{ .ok = cached_path },
    });

    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTerminalImageLoadSlice().len);

    var frame_index: u64 = 1;
    while (app.hasActiveScreenTransition()) : (frame_index += 1) {
        try app.update(.{ .frame = .{ .now_ns = frame_index * 16, .delta_ns = 16, .index = frame_index } }, &tc.ctx);
    }
    defer {
        for (tc.ctx.pendingTerminalImageLoadSlice()) |entry| {
            std.testing.allocator.free(entry.path);
            const load_ctx: *GameDetailTerminalImageLoadContext = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.destroy(load_ctx);
        }
        tc.ctx.pending_terminal_image_loads_len = 0;
    }

    const pending = tc.ctx.pendingTerminalImageLoadSlice();
    try std.testing.expectEqual(@as(usize, 1), pending.len);
    try std.testing.expectEqualStrings("/tmp/cover.png", pending[0].path);
}

test "returning to detail retries deferred terminal image load without transition" {
    var app = App.create(.{ .interface = .{ .transition = "none" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.screen = .forums;
    app.game_detail.image_request_id = 3;
    const cached_path = try std.testing.allocator.dupe(u8, "/tmp/cover.png");

    try app.finishGameDetailImageCache(&tc.ctx, .{
        .request_id = 3,
        .result = .{ .ok = cached_path },
    });
    try std.testing.expectEqual(@as(usize, 0), tc.ctx.pendingTerminalImageLoadSlice().len);

    try app.showScreen(.game_detail, &tc.ctx);
    defer {
        for (tc.ctx.pendingTerminalImageLoadSlice()) |entry| {
            std.testing.allocator.free(entry.path);
            const load_ctx: *GameDetailTerminalImageLoadContext = @ptrCast(@alignCast(entry.ctx));
            std.testing.allocator.destroy(load_ctx);
        }
        tc.ctx.pending_terminal_image_loads_len = 0;
    }

    const pending = tc.ctx.pendingTerminalImageLoadSlice();
    try std.testing.expectEqual(@as(usize, 1), pending.len);
    try std.testing.expectEqualStrings("/tmp/cover.png", pending[0].path);
}

test "stale terminal image load is unloaded" {
    var app = App.create(.{}, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.game_detail.image_request_id = 5;

    const load_ctx = try std.testing.allocator.create(GameDetailTerminalImageLoadContext);
    load_ctx.* = .{ .request_id = 4 };

    app.finishGameDetailTerminalImageLoad(&tc.ctx, .{
        .load_ctx = load_ctx,
        .handle = .{ .id = 9, .generation = 1 },
    });

    const pending = tc.ctx.pendingTerminalImageUnloadSlice();
    try std.testing.expectEqual(@as(usize, 1), pending.len);
    try std.testing.expectEqual(@as(u32, 9), pending[0].id);
    try std.testing.expect(app.game_detail.terminal_image_handle == null);
}

test "search loading enters results without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    try app.search.input.?.update(.clear);
    try app.search.input.?.update(.{ .insert = 'r' });
    try app.search.input.?.update(.{ .insert = 'o' });
    try app.search.input.?.update(.{ .insert = 'o' });
    try app.search.input.?.update(.{ .insert = 't' });
    tc.resetTransient();
    try app.startSearch(&tc.ctx);
    defer {
        const task: *SearchTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.free(task.query);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.search_results, app.screen);
    try std.testing.expect(app.search.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "search completion starts content transition when results are visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    app.screen = .search_results;
    app.search.request_id = 7;
    tc.resetTransient();
    try app.finishSearch(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = results } });

    try std.testing.expect(app.search.load_state == .loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.search_results, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.search_results, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "search completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    app.screen = .main_menu;
    app.search.request_id = 7;
    tc.resetTransient();
    try app.finishSearch(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = results } });

    try std.testing.expect(app.search.load_state == .loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "collection loading enters collection without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    try app.collection.username_input.?.update(.clear);
    try app.collection.username_input.?.update(.{ .insert = 'h' });
    try app.collection.username_input.?.update(.{ .insert = 'i' });
    try app.collection.username_input.?.update(.{ .insert = 'r' });
    try app.collection.username_input.?.update(.{ .insert = 'o' });
    tc.resetTransient();
    try app.startCollectionLoad(&tc.ctx);
    defer {
        const task: *CollectionTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.free(task.username);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.collection, app.screen);
    try std.testing.expect(app.collection.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "collection completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN"), .owned = true };

    app.screen = .collection;
    app.collection.request_id = 7;
    tc.resetTransient();
    try app.finishCollectionLoad(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = items } });

    try std.testing.expect(app.collection.load_state == .loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.collection, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.collection, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "collection completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const items = try std.testing.allocator.alloc(bgg_model.CollectionItem, 1);
    items[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "CATAN"), .owned = true };

    app.screen = .main_menu;
    app.collection.request_id = 7;
    tc.resetTransient();
    try app.finishCollectionLoad(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = items } });

    try std.testing.expect(app.collection.load_state == .loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "forum list loading enters forums without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const games = try std.testing.allocator.alloc(bgg_model.Game, 1);
    games[0] = .{ .id = 13, .name = try std.testing.allocator.dupe(u8, "Catan") };
    try app.game_detail.setLoaded(std.testing.allocator, games, 90);

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    tc.resetTransient();
    try app.startForumList(&tc.ctx);
    defer {
        const task: *ForumListTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.forums, app.screen);
    try std.testing.expect(app.forums.load_state == .loading_forums);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "forum list completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const forums = try std.testing.allocator.alloc(bgg_model.Forum, 1);
    forums[0] = .{
        .id = 10,
        .title = try std.testing.allocator.dupe(u8, "General"),
    };

    app.screen = .forums;
    app.forums.request_id = 7;
    tc.resetTransient();
    try app.finishForumList(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = forums } });

    try std.testing.expect(app.forums.load_state == .forums_loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.forums, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.forums, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "forum list completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const forums = try std.testing.allocator.alloc(bgg_model.Forum, 1);
    forums[0] = .{
        .id = 10,
        .title = try std.testing.allocator.dupe(u8, "General"),
    };

    app.screen = .main_menu;
    app.forums.request_id = 7;
    tc.resetTransient();
    try app.finishForumList(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = forums } });

    try std.testing.expect(app.forums.load_state == .forums_loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "thread list loading enters forums without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const forums = try std.testing.allocator.alloc(bgg_model.Forum, 1);
    forums[0] = .{
        .id = 10,
        .title = try std.testing.allocator.dupe(u8, "General"),
    };
    try app.forums.setForumsLoaded(std.testing.allocator, forums);
    app.screen = .forums;

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());
    app.screen = .forums;

    tc.resetTransient();
    try app.startForumThreads(&tc.ctx, 0, 1);
    defer {
        const task: *ForumThreadsTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.forums, app.screen);
    try std.testing.expect(app.forums.load_state == .loading_threads);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "thread list completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules question"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };

    app.screen = .forums;
    app.forums.thread_list_request_id = 7;
    tc.resetTransient();
    try app.finishForumThreads(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = .{ .threads = threads, .page = 1, .total_pages = 1 } } });

    try std.testing.expect(app.forums.load_state == .threads_loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.forums, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.forums, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "thread list completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules question"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };

    app.screen = .main_menu;
    app.forums.thread_list_request_id = 7;
    tc.resetTransient();
    try app.finishForumThreads(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = .{ .threads = threads, .page = 1, .total_pages = 1 } } });

    try std.testing.expect(app.forums.load_state == .threads_loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "thread loading enters thread without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const threads = try std.testing.allocator.alloc(bgg_model.ThreadSummary, 1);
    threads[0] = .{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules question"),
        .author = try std.testing.allocator.dupe(u8, "hiro"),
    };
    try app.forums.setThreadsLoaded(std.testing.allocator, .{ .threads = threads, .page = 1, .total_pages = 1 });
    app.screen = .forums;

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());
    app.screen = .forums;

    tc.resetTransient();
    try app.startThread(&tc.ctx, 0);
    defer {
        const task: *ThreadTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.thread, app.screen);
    try std.testing.expect(app.thread.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "thread completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const thread = bgg_model.Thread{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules question"),
    };

    app.screen = .thread;
    app.thread.request_id = 7;
    tc.resetTransient();
    try app.finishThread(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = thread } });

    try std.testing.expect(app.thread.load_state == .loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.thread, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.thread, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "thread completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    const thread = bgg_model.Thread{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules question"),
    };

    app.screen = .main_menu;
    app.thread.request_id = 7;
    tc.resetTransient();
    try app.finishThread(&tc.ctx, .{ .request_id = 7, .result = .{ .ok = thread } });

    try std.testing.expect(app.thread.load_state == .loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(!tc.ctx.frame_requested);
}

test "hot games loading enters hot games without screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    try app.showScreen(.settings, &tc.ctx);
    try std.testing.expect(app.hasActiveScreenTransition());

    tc.resetTransient();
    try app.showScreen(.hot_games, &tc.ctx);
    defer {
        const task: *HotGamesTask = @ptrCast(@alignCast(tc.ctx.pendingTaskWithSlice()[0].ctx));
        std.testing.allocator.free(task.token);
        std.testing.allocator.destroy(task);
    }

    try std.testing.expectEqual(Screen.hot_games, app.screen);
    try std.testing.expect(app.hot_games.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 1), tc.ctx.pending_tasks_with_len);
}

test "hot games loading re-entry clears screen transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();

    app.hot_games.setLoading();
    app.screen = .settings;
    tc.resetTransient();
    try app.showScreen(.hot_games, &tc.ctx);

    try std.testing.expectEqual(Screen.hot_games, app.screen);
    try std.testing.expect(app.hot_games.load_state == .loading);
    try std.testing.expect(!app.hasActiveScreenTransition());
    try std.testing.expect(tc.ctx.frame_requested);
    try std.testing.expectEqual(@as(u8, 0), tc.ctx.pending_tasks_with_len);
}

test "hot games completion starts content transition when visible" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();
    defer freePendingHotGameStatsTasks(&tc.ctx);

    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{ .id = 13, .rank = 1, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    app.screen = .hot_games;
    tc.resetTransient();
    try app.finishHotGamesLoad(&tc.ctx, .{ .ok = games });

    try std.testing.expect(app.hot_games.load_state == .loaded);
    try std.testing.expect(app.hasActiveScreenTransition());
    try std.testing.expectEqual(Screen.hot_games, app.transition_from_screen.?);
    try std.testing.expectEqual(Screen.hot_games, app.transition_to_screen.?);
    try std.testing.expect(tc.ctx.frame_requested);
}

test "hot games completion stores hidden result without transition" {
    var app = App.create(.{ .api = .{ .token = "token" }, .interface = .{ .transition = "sweep" } }, .{});

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.init(&tc.ctx);
    defer app.deinitOwnedState();
    defer freePendingHotGameStatsTasks(&tc.ctx);

    const games = try std.testing.allocator.alloc(bgg_model.HotGame, 1);
    games[0] = .{ .id = 13, .rank = 1, .name = try std.testing.allocator.dupe(u8, "CATAN") };

    app.screen = .main_menu;
    tc.resetTransient();
    try app.finishHotGamesLoad(&tc.ctx, .{ .ok = games });

    try std.testing.expect(app.hot_games.load_state == .loaded);
    try std.testing.expect(!app.hasActiveScreenTransition());
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

test "hot games slash starts filter before global search shortcut" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.screen = .hot_games;

    const msg = app.handleEvent(.{ .key_press = .{ .codepoint = '/' } }).?;

    try std.testing.expect(msg == .hot_games);
    try std.testing.expect(msg.hot_games == .filter_start);
}

test "hot games global shortcuts work after clearing filter" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.screen = .hot_games;
    app.hot_games.filter_input = try ui.TextInput.init(std.testing.allocator, .{ .value = "ca" });
    defer app.deinitOwnedState();

    try app.hot_games.applyFilter(std.testing.allocator, "");
    const clear_msg = app.handleEvent(.{ .key_press = .{ .codepoint = chasen.Key.escape } }).?;
    try std.testing.expect(clear_msg == .hot_games);
    try std.testing.expect(clear_msg.hot_games == .filter_clear);

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

    try std.testing.expect(msg == .search);
    try std.testing.expect(msg.search == .filter_start);
}

test "successful search completion loads result list" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    defer app.deinitOwnedState();

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.search.request_id = 7;
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Root") };

    try app.finishSearch(&tc.ctx, .{
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

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    app.search.request_id = 3;
    try app.finishSearch(&tc.ctx, .{
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

    app.search.request_id = 2;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    try app.finishSearch(&tc.ctx, .{
        .request_id = 1,
        .result = .{ .ok = results },
    });

    try std.testing.expect(app.search.load_state == .idle);
    try std.testing.expectEqual(@as(usize, 0), app.search.list.items.len);
}

test "invalid search submit invalidates in-flight search results" {
    var app = App.create(.{ .api = .{ .token = "token" } }, .{});
    app.allocator = std.testing.allocator;
    app.search.input = try ui.TextInput.init(std.testing.allocator, .{ .value = "go" });
    defer app.deinitOwnedState();

    app.search.request_id = 1;

    var tc: chasen.testing.TestCtx(App.Msg) = .{};
    try app.startSearch(&tc.ctx);

    try std.testing.expectEqual(@as(u64, 2), app.search.request_id);
    try std.testing.expect(app.search.load_state == .failed);

    const results = try std.testing.allocator.alloc(bgg_model.GameSearchResult, 1);
    results[0] = .{ .id = 1, .name = try std.testing.allocator.dupe(u8, "Old Result") };

    try app.finishSearch(&tc.ctx, .{
        .request_id = 1,
        .result = .{ .ok = results },
    });

    try std.testing.expect(app.search.load_state == .failed);
    try std.testing.expectEqual(@as(usize, 0), app.search.list.items.len);
}

test "effective detail content width uses clamped terminal width" {
    var app = App.create(.{
        .api = .{ .token = "token" },
        .display = .{ .detail_width = 120, .show_images = true, .image_protocol = .auto },
    }, .{});

    app.terminal_size = .{ .width = 92, .height = 24 };

    try std.testing.expectEqual(@as(usize, 58), app.effectiveDetailContentWidth());
}
