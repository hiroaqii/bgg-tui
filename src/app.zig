const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const config_mod = @import("config.zig");

pub const Screen = enum {
    main_menu,
};

pub const App = struct {
    config: config_mod.Config,
    screen: Screen = .main_menu,
    shell: ui.Panel = ui.Panel.init(.{}),
    status: ui.StatusLine = ui.StatusLine.init(.{
        .left = "bgg-tui",
        .center = "main menu",
        .right = "Esc/q: quit",
    }),

    pub const Msg = union(enum) {
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
        _ = self;
        switch (msg) {
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
        self.status.view(&status_area, .{});
    }

    pub fn handleEvent(self: *const App, event: chasen.Event) ?Msg {
        _ = self;
        return switch (event) {
            .key_press => |key| if (key.matches(chasen.Key.escape, .{}) or key.codepoint == 'q') .quit else null,
            else => null,
        };
    }

    fn viewCurrentScreen(self: *const App, sfc: *chasen.Surface) !void {
        switch (self.screen) {
            .main_menu => try self.viewMainMenu(sfc),
        }
    }

    fn viewMainMenu(self: *const App, sfc: *chasen.Surface) !void {
        const token_status = if (self.config.apiClientToken() == null) "missing" else "configured";
        _ = sfc.textAt(0, 0, "Main menu", .{ .bold = true });
        _ = try sfc.printAt(0, 2, .{ .fg = .gray }, "BGG API token: {s}", .{token_status});
        _ = sfc.textAt(0, 4, "Phase 6 starts with the Chasen shell. Screens will be added incrementally.", .{ .dim = true });
    }
};

test "app initializes with main menu screen" {
    const app = App.create(.{});

    try std.testing.expectEqual(Screen.main_menu, app.screen);
    try std.testing.expectEqual(@as(?[]const u8, null), app.config.apiClientToken());
}
