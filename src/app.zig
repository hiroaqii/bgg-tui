const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const config_mod = @import("config.zig");

const menu_items = [_]ui.Menu.Item{
    .{ .label = "Hot Games", .shortcut = "h" },
    .{ .label = "Search Games", .shortcut = "/" },
    .{ .label = "Collection", .shortcut = "c" },
    .{ .label = "Settings", .shortcut = "s" },
};

pub const Screen = enum {
    main_menu,
    hot_games,
    search,
    collection,
    settings,
};

pub const App = struct {
    config: config_mod.Config,
    screen: Screen = .main_menu,
    menu: ui.Menu = ui.Menu.init(.{ .items = &menu_items }),
    shell: ui.Panel = ui.Panel.init(.{}),

    pub const Msg = union(enum) {
        menu: ui.Menu.Msg,
        show_screen: Screen,
        quit,
    };

    pub fn create(config: config_mod.Config) App {
        return .{ .config = config };
    }

    pub fn init(self: *App, ctx: *chasen.Ctx(Msg)) !void {
        _ = self;
        _ = ctx;
    }

    pub fn update(self: *App, msg: Msg, ctx: *chasen.Ctx(Msg)) !void {
        switch (msg) {
            .menu => |menu_msg| switch (menu_msg) {
                .move_prev, .move_next => self.menu.update(menu_msg),
                .activate => |index| self.screen = screenForMenuIndex(index) orelse self.screen,
            },
            .show_screen => |screen| self.screen = screen,
            .quit => ctx.quit(),
        }
    }

    pub fn view(self: *const App, sfc: *chasen.Surface) !void {
        const size = sfc.size();
        if (size.width == 0 or size.height == 0) return;

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
            .right = "m: menu  Esc/q: quit",
        });
        status.view(&status_area, .{});
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        switch (event) {
            .key_press => |key| {
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
            if (self.menu.handleEvent(event)) |msg| return .{ .menu = msg };
        }
        return null;
    }

    fn viewCurrentScreen(self: *const App, sfc: *chasen.Surface) !void {
        switch (self.screen) {
            .main_menu => try self.viewMainMenu(sfc),
            .hot_games => self.viewPlaceholder(sfc, "Hot Games", "Loading and display will be added in the next small steps."),
            .search => self.viewPlaceholder(sfc, "Search Games", "Search input and results are pending."),
            .collection => self.viewPlaceholder(sfc, "Collection", "Collection loading is planned after the MVP list flow."),
            .settings => self.viewPlaceholder(sfc, "Settings", "Minimum settings screen is pending."),
        }
    }

    fn viewMainMenu(self: *const App, sfc: *chasen.Surface) !void {
        const token_status = if (self.config.apiClientToken() == null) "missing" else "configured";
        _ = sfc.textAt(0, 0, "Main menu", .{ .bold = true });
        _ = try sfc.printAt(0, 2, .{ .fg = .gray }, "BGG API token: {s}", .{token_status});

        var menu_area = sfc.child(.{
            .col = 0,
            .row = 4,
            .width = @min(sfc.size().width, 36),
            .height = @min(sfc.size().height -| 4, @as(u16, menu_items.len)),
        });
        self.menu.view(&menu_area, .{
            .shortcut_col = 24,
            .focused_style = .{ .bold = true, .fg = .{ .index = 14 } },
        });

        _ = sfc.textAt(0, 10, "Use Up/Down and Enter, or h, /, c, s shortcuts.", .{ .dim = true });
    }

    fn viewPlaceholder(self: *const App, sfc: *chasen.Surface, title: []const u8, message: []const u8) void {
        _ = self;
        _ = sfc.textAt(0, 0, title, .{ .bold = true, .fg = .{ .index = 14 } });
        _ = sfc.textAt(0, 2, message, .{ .fg = .gray });
        _ = sfc.textAt(0, 4, "m: menu  Esc/q: quit", .{ .dim = true });
    }
};

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
        .main_menu => "main menu",
        .hot_games => "hot games",
        .search => "search",
        .collection => "collection",
        .settings => "settings",
    };
}

test "app initializes with main menu screen" {
    const app = App.create(.{});

    try std.testing.expectEqual(Screen.main_menu, app.screen);
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
    try std.testing.expectEqualStrings("main menu", screenTitle(.main_menu));
    try std.testing.expectEqualStrings("hot games", screenTitle(.hot_games));
    try std.testing.expectEqualStrings("search", screenTitle(.search));
    try std.testing.expectEqualStrings("collection", screenTitle(.collection));
    try std.testing.expectEqualStrings("settings", screenTitle(.settings));
}
