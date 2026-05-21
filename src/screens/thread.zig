const std = @import("std");

const bgg_html = @import("../bgg/html.zig");
const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const format = @import("../format.zig");
const ui = @import("chasen_ui");

pub const LoadState = union(enum) {
    idle,
    loading,
    loaded,
    failed: []const u8,
};

pub const State = struct {
    thread_id: u32 = 0,
    load_state: LoadState = .idle,
    thread: ?bgg_model.Thread = null,
    rendered_text: []u8 = "",
    lines: []const []const u8 = &.{},
    scroll: usize = 0,
    sort_newest: bool = false,
    wrap_width: usize = 90,
    visible_height: usize = 1,
    browser_error_url: []u8 = "",

    pub fn startLoad(self: *State, allocator: std.mem.Allocator, thread_id: u32, wrap_width: usize) void {
        self.deinit(allocator);
        self.thread_id = thread_id;
        self.wrap_width = @max(wrap_width, 20);
        self.load_state = .loading;
    }

    pub fn setFailed(self: *State, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    pub fn setLoaded(self: *State, allocator: std.mem.Allocator, thread: bgg_model.Thread) !void {
        self.clearThread(allocator);
        self.thread = thread;
        try self.rebuildLines(allocator);
        self.scroll = 0;
        self.load_state = .loaded;
    }

    pub fn moveUp(self: *State) void {
        if (self.scroll > 0) self.scroll -= 1;
    }

    pub fn moveDown(self: *State, visible_height: usize) void {
        const max = self.maxScroll(visible_height);
        if (self.scroll < max) self.scroll += 1;
    }

    pub fn setVisibleHeight(self: *State, visible_height: usize) void {
        self.visible_height = @max(visible_height, 1);
        self.scroll = @min(self.scroll, self.maxScroll(self.visible_height));
    }

    pub fn toggleSort(self: *State, allocator: std.mem.Allocator) !void {
        if (self.thread == null) return;
        self.sort_newest = !self.sort_newest;
        self.sortArticles();
        try self.rebuildLines(allocator);
        self.scroll = 0;
    }

    pub fn setBrowserErrorUrl(self: *State, allocator: std.mem.Allocator, url: []const u8) !void {
        allocator.free(self.browser_error_url);
        self.browser_error_url = try allocator.dupe(u8, url);
    }

    pub fn clearBrowserErrorUrl(self: *State, allocator: std.mem.Allocator) void {
        allocator.free(self.browser_error_url);
        self.browser_error_url = "";
    }

    pub fn visibleRange(self: *const State, visible_height: usize) ui.Viewport.Range {
        return ui.Viewport.init(.{
            .total = self.lines.len,
            .height = visible_height,
            .offset = self.scroll,
        }).visibleRange();
    }

    pub fn maxScroll(self: *const State, visible_height: usize) usize {
        return ui.Viewport.init(.{
            .total = self.lines.len,
            .height = visible_height,
            .offset = self.scroll,
        }).maxOffset();
    }

    pub fn postCount(self: *const State) usize {
        const thread = self.thread orelse return 0;
        return thread.articles.len;
    }

    pub fn subject(self: *const State) []const u8 {
        const thread = self.thread orelse return "Thread";
        return thread.subject;
    }

    pub fn sortLabel(self: *const State) []const u8 {
        return if (self.sort_newest) "↓New" else "↑Old";
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.clearThread(allocator);
        self.thread_id = 0;
        self.scroll = 0;
        self.sort_newest = false;
        self.visible_height = 1;
        self.load_state = .idle;
    }

    fn clearThread(self: *State, allocator: std.mem.Allocator) void {
        self.clearBrowserErrorUrl(allocator);
        allocator.free(self.lines);
        allocator.free(self.rendered_text);
        if (self.thread) |thread| bgg_xml.freeThread(allocator, thread);
        self.thread = null;
        self.rendered_text = "";
        self.lines = &.{};
    }

    fn rebuildLines(self: *State, allocator: std.mem.Allocator) !void {
        allocator.free(self.lines);
        allocator.free(self.rendered_text);
        self.lines = &.{};
        self.rendered_text = "";

        const thread = self.thread orelse return;
        self.rendered_text = try renderArticles(allocator, thread.articles, self.wrap_width);
        self.lines = try splitLines(allocator, self.rendered_text);
    }

    fn sortArticles(self: *State) void {
        if (self.thread) |*thread| {
            std.mem.sort(bgg_model.Article, thread.articles, self.sort_newest, articleDateLessThan);
        }
    }
};

pub const Layout = struct {
    title_row: u16,
    meta_row: u16,
    content_row: u16,
    content_height: usize,
    scroll_row: u16,
    footer_row: u16,
};

pub const LayoutOptions = struct {
    outer_reserved_rows: u16 = 0,
};

pub fn layout(area_height: u16, density: []const u8, options: LayoutOptions) Layout {
    if (area_height == 0) {
        return .{ .title_row = 0, .meta_row = 0, .content_row = 0, .content_height = 1, .scroll_row = 0, .footer_row = 0 };
    }

    const effective_height = area_height + options.outer_reserved_rows;
    const desired_visible = contentHeight(effective_height, density);
    const block_height = @min(@as(usize, area_height), desired_visible + threadBlockOverhead());
    const title_row: u16 = @intCast((@as(usize, area_height) - block_height) / 2);
    const meta_row = @min(area_height - 1, title_row + 1);
    const content_row = @min(area_height - 1, title_row + 3);
    const max_visible = if (area_height > content_row + 3) area_height - content_row - 3 else 1;
    const visible = @max(@as(usize, 1), @min(desired_visible, @as(usize, max_visible)));
    const visible_u16: u16 = @intCast(@min(visible, std.math.maxInt(u16)));
    const scroll_row = @min(area_height - 1, content_row + visible_u16);

    return .{
        .title_row = title_row,
        .meta_row = meta_row,
        .content_row = content_row,
        .content_height = visible,
        .scroll_row = scroll_row,
        .footer_row = @min(area_height - 1, scroll_row + 2),
    };
}

pub fn contentHeight(area_height: u16, density: []const u8) usize {
    return @max(@as(usize, 1), @as(usize, area_height) -| densityOverhead(density) -| threadExtraOverhead());
}

fn densityOverhead(density: []const u8) usize {
    if (std.mem.eql(u8, density, "compact")) return 8;
    if (std.mem.eql(u8, density, "relaxed")) return 16;
    return 12;
}

fn threadExtraOverhead() usize {
    return 2;
}

fn threadBlockOverhead() usize {
    return 6;
}

fn renderArticles(allocator: std.mem.Allocator, articles: []const bgg_model.Article, wrap_width: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    for (articles, 0..) |article, index| {
        const date = try dateText(allocator, article.post_date);
        defer allocator.free(date);
        try out.writer.print("■ {s}  {s}\n", .{ article.username, date });

        const body = try bgg_html.toText(allocator, article.body, .{
            .wrap_width = wrap_width,
            .linkify_urls = true,
        });
        defer allocator.free(body);
        try out.writer.writeAll(body);
        try out.writer.writeByte('\n');

        if (index + 1 < articles.len) {
            try out.writer.writeByte('\n');
            try writeSeparator(&out.writer, wrap_width);
            try out.writer.writeAll("\n\n");
        }
    }

    return try out.toOwnedSlice();
}

fn splitLines(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    errdefer lines.deinit(allocator);

    var start: usize = 0;
    var index: usize = 0;
    while (index <= text.len) : (index += 1) {
        if (index == text.len or text[index] == '\n') {
            try lines.append(allocator, text[start..index]);
            start = index + 1;
        }
    }

    return try lines.toOwnedSlice(allocator);
}

fn writeSeparator(writer: *std.Io.Writer, width: usize) !void {
    var remaining = @max(width, 1);
    while (remaining > 0) : (remaining -= 1) {
        try writer.writeAll("─");
    }
}

fn dateText(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    if (value.len == 0) return try allocator.dupe(u8, "");

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    format.writeBggDate(&out.writer, value, .yyyy_mm_dd, null) catch {
        try out.writer.writeAll(value);
    };
    return try out.toOwnedSlice();
}

fn articleDateLessThan(newest_first: bool, lhs: bgg_model.Article, rhs: bgg_model.Article) bool {
    const order = compareArticleDate(lhs.post_date, rhs.post_date);
    if (order == .eq) return lhs.id < rhs.id;
    return if (newest_first) order == .gt else order == .lt;
}

fn compareArticleDate(lhs: []const u8, rhs: []const u8) std.math.Order {
    const lhs_date = format.parseBggDate(lhs) catch return std.mem.order(u8, lhs, rhs);
    const rhs_date = format.parseBggDate(rhs) catch return std.mem.order(u8, lhs, rhs);
    const lhs_days = daysFromDate(lhs_date);
    const rhs_days = daysFromDate(rhs_date);
    return std.math.order(lhs_days, rhs_days);
}

fn daysFromDate(date: format.Date) i64 {
    const y: i64 = date.year - @intFromBool(date.month <= 2);
    const era = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe = y - era * 400;
    const month: i64 = date.month;
    const day: i64 = date.day;
    const doy = @divFloor(153 * (month + (if (month > 2) @as(i64, -3) else @as(i64, 9))) + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

test "thread state renders article text lines" {
    var state: State = .{};
    defer state.deinit(std.testing.allocator);

    const articles = try std.testing.allocator.alloc(bgg_model.Article, 1);
    articles[0] = .{
        .id = 1,
        .username = try std.testing.allocator.dupe(u8, "hiro"),
        .post_date = try std.testing.allocator.dupe(u8, "Sat, 01 Jan 2025 10:00:00 +0000"),
        .body = try std.testing.allocator.dupe(u8, "<p>Hello<br>World</p>"),
    };
    const thread = bgg_model.Thread{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules"),
        .articles = articles,
    };

    try state.setLoaded(std.testing.allocator, thread);

    try std.testing.expectEqual(@as(usize, 1), state.postCount());
    try std.testing.expect(std.mem.indexOf(u8, state.rendered_text, "■ hiro") != null);
    try std.testing.expect(std.mem.indexOf(u8, state.rendered_text, "Hello") != null);
}

test "thread sort toggles newest first and resets scroll" {
    var state: State = .{};
    defer state.deinit(std.testing.allocator);

    const articles = try std.testing.allocator.alloc(bgg_model.Article, 2);
    articles[0] = .{
        .id = 1,
        .username = try std.testing.allocator.dupe(u8, "old"),
        .post_date = try std.testing.allocator.dupe(u8, "Sat, 01 Jan 2025 10:00:00 +0000"),
        .body = try std.testing.allocator.dupe(u8, "old body"),
    };
    articles[1] = .{
        .id = 2,
        .username = try std.testing.allocator.dupe(u8, "new"),
        .post_date = try std.testing.allocator.dupe(u8, "Sun, 02 Jan 2025 10:00:00 +0000"),
        .body = try std.testing.allocator.dupe(u8, "new body"),
    };
    const thread = bgg_model.Thread{
        .id = 100,
        .subject = try std.testing.allocator.dupe(u8, "Rules"),
        .articles = articles,
    };

    try state.setLoaded(std.testing.allocator, thread);
    state.scroll = 1;
    try state.toggleSort(std.testing.allocator);

    try std.testing.expect(state.sort_newest);
    try std.testing.expectEqual(@as(usize, 0), state.scroll);
    try std.testing.expectEqual(@as(u32, 2), state.thread.?.articles[0].id);
}

test "thread layout uses available height with outer chrome compensation" {
    const normal = layout(44, "normal", .{ .outer_reserved_rows = 3 });
    try std.testing.expectEqual(@as(u16, 2), normal.title_row);
    try std.testing.expectEqual(@as(u16, 3), normal.meta_row);
    try std.testing.expectEqual(@as(u16, 5), normal.content_row);
    try std.testing.expectEqual(@as(usize, 33), normal.content_height);
    try std.testing.expectEqual(@as(u16, 38), normal.scroll_row);
    try std.testing.expectEqual(@as(u16, 40), normal.footer_row);
    try std.testing.expectEqual(@as(u16, 3), normal.content_row - normal.title_row);

    const small = layout(5, "normal", .{});
    try std.testing.expect(small.content_height >= 1);
    try std.testing.expect(small.footer_row < 5);
}
