const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const bgg_model = @import("../bgg/model.zig");
const bgg_xml = @import("../bgg/xml.zig");
const format = @import("../format.zig");

pub const Mode = enum {
    forum_list,
    thread_list,
};

pub const LoadState = union(enum) {
    idle,
    loading_forums,
    forums_loaded,
    loading_threads,
    threads_loaded,
    failed: []const u8,
};

pub const State = struct {
    game_id: u32 = 0,
    game_name: []const u8 = "",
    mode: Mode = .forum_list,
    load_state: LoadState = .idle,
    forums: []bgg_model.Forum = &.{},
    forum_labels: []const []const u8 = &.{},
    forum_list: ui.List = ui.List.init(.{}),
    selected_forum_index: usize = 0,
    thread_page: bgg_model.ThreadList = .{},
    thread_labels: []const []const u8 = &.{},
    thread_list: ui.List = ui.List.init(.{}),

    pub fn startForumLoad(self: *State, allocator: std.mem.Allocator, game_id: u32, game_name: []const u8) !void {
        self.deinit(allocator);
        self.game_id = game_id;
        self.game_name = try allocator.dupe(u8, game_name);
        self.mode = .forum_list;
        self.load_state = .loading_forums;
    }

    pub fn setFailed(self: *State, message: []const u8) void {
        self.load_state = .{ .failed = message };
    }

    pub fn setForumsLoaded(self: *State, allocator: std.mem.Allocator, forums: []bgg_model.Forum) !void {
        self.clearForums(allocator);
        self.clearThreads(allocator);
        sortForumsByLastPostDate(forums);
        self.forums = forums;
        self.forum_labels = try buildForumLabels(allocator, forums);
        self.forum_list = ui.List.init(.{ .items = self.forum_labels });
        self.mode = .forum_list;
        self.load_state = .forums_loaded;
    }

    pub fn startThreadLoad(self: *State, allocator: std.mem.Allocator, visible_index: usize) void {
        self.clearThreads(allocator);
        self.selected_forum_index = @min(visible_index, if (self.forums.len == 0) 0 else self.forums.len - 1);
        self.mode = .thread_list;
        self.load_state = .loading_threads;
    }

    pub fn startThreadPageLoad(self: *State, allocator: std.mem.Allocator, page: u32) void {
        self.clearThreads(allocator);
        self.thread_page.page = if (page == 0) 1 else page;
        self.mode = .thread_list;
        self.load_state = .loading_threads;
    }

    pub fn setThreadsLoaded(self: *State, allocator: std.mem.Allocator, thread_page: bgg_model.ThreadList) !void {
        self.clearThreads(allocator);
        self.thread_page = thread_page;
        self.thread_labels = try buildThreadLabels(allocator, thread_page.threads);
        self.thread_list = ui.List.init(.{ .items = self.thread_labels });
        self.mode = .thread_list;
        self.load_state = .threads_loaded;
    }

    pub fn backToForumList(self: *State, allocator: std.mem.Allocator) void {
        self.clearThreads(allocator);
        self.mode = .forum_list;
        self.load_state = .forums_loaded;
    }

    pub fn updateForumList(self: *State, msg: ui.List.Msg) void {
        self.forum_list.update(msg);
    }

    pub fn updateThreadList(self: *State, msg: ui.List.Msg) void {
        self.thread_list.update(msg);
    }

    pub fn selectedForum(self: *const State) ?bgg_model.Forum {
        if (self.selected_forum_index >= self.forums.len) return null;
        return self.forums[self.selected_forum_index];
    }

    pub fn selectedForumFromVisible(self: *const State, visible_index: usize) ?bgg_model.Forum {
        if (visible_index >= self.forums.len) return null;
        return self.forums[visible_index];
    }

    pub fn canOpenNextPage(self: *const State) bool {
        return self.mode == .thread_list and self.thread_page.page < self.thread_page.total_pages;
    }

    pub fn canOpenPreviousPage(self: *const State) bool {
        return self.mode == .thread_list and self.thread_page.page > 1;
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        allocator.free(self.game_name);
        self.game_name = "";
        self.game_id = 0;
        self.clearThreads(allocator);
        self.clearForums(allocator);
        self.mode = .forum_list;
        self.load_state = .idle;
    }

    fn clearForums(self: *State, allocator: std.mem.Allocator) void {
        freeLabels(allocator, self.forum_labels);
        bgg_xml.freeForums(allocator, self.forums);
        self.forums = &.{};
        self.forum_labels = &.{};
        self.forum_list = ui.List.init(.{});
        self.selected_forum_index = 0;
    }

    fn clearThreads(self: *State, allocator: std.mem.Allocator) void {
        freeLabels(allocator, self.thread_labels);
        bgg_xml.freeThreadList(allocator, self.thread_page);
        self.thread_page = .{};
        self.thread_labels = &.{};
        self.thread_list = ui.List.init(.{});
    }
};

pub fn buildForumLabels(allocator: std.mem.Allocator, forums: []const bgg_model.Forum) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, forums.len);
    errdefer allocator.free(labels);
    var initialized: usize = 0;
    errdefer {
        for (labels[0..initialized]) |label| allocator.free(label);
    }

    for (forums, 0..) |forum, index| {
        labels[index] = try forumLabel(allocator, forum, forumTitleWidth(forums), forumThreadDigitWidth(forums));
        initialized += 1;
    }
    return labels;
}

pub fn buildThreadLabels(allocator: std.mem.Allocator, threads: []const bgg_model.ThreadSummary) ![]const []const u8 {
    const labels = try allocator.alloc([]const u8, threads.len);
    errdefer allocator.free(labels);
    var initialized: usize = 0;
    errdefer {
        for (labels[0..initialized]) |label| allocator.free(label);
    }

    for (threads, 0..) |thread, index| {
        labels[index] = try allocator.dupe(u8, thread.subject);
        initialized += 1;
    }
    return labels;
}

pub fn freeLabels(allocator: std.mem.Allocator, labels: []const []const u8) void {
    for (labels) |label| allocator.free(label);
    allocator.free(labels);
}

fn forumLabel(allocator: std.mem.Allocator, forum: bgg_model.Forum, title_width: usize, thread_digits: usize) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.print("{s}", .{forum.title});
    try writeSpaces(&out.writer, title_width -| forum.title.len);
    // Match the Go version's two-column forum list: padded title, then thread
    // count and last-post date as muted metadata.
    const thread_count = try std.fmt.allocPrint(allocator, "{d}", .{forum.num_threads});
    defer allocator.free(thread_count);
    try out.writer.writeAll("  ");
    try writeSpaces(&out.writer, thread_digits -| thread_count.len);
    try out.writer.print("{s} threads", .{thread_count});
    if (forum.last_post_date.len > 0) {
        const date = try dateText(allocator, forum.last_post_date);
        defer allocator.free(date);
        try out.writer.print(" · {s}", .{date});
    }
    return try out.toOwnedSlice();
}

pub fn threadMetaText(allocator: std.mem.Allocator, thread: bgg_model.ThreadSummary) ![]const u8 {
    const date = try dateText(allocator, thread.last_post_date);
    defer allocator.free(date);
    return try std.fmt.allocPrint(allocator, "{s} · {s} · {d} replies", .{
        date,
        thread.author,
        thread.num_articles -| 1,
    });
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

fn forumTitleWidth(forums: []const bgg_model.Forum) usize {
    var width: usize = 0;
    for (forums) |forum| {
        width = @max(width, forum.title.len);
    }
    return width;
}

fn forumThreadDigitWidth(forums: []const bgg_model.Forum) usize {
    var max_threads: u32 = 0;
    for (forums) |forum| {
        max_threads = @max(max_threads, forum.num_threads);
    }
    return digitWidth(max_threads);
}

fn digitWidth(value: u32) usize {
    var digits: usize = 1;
    var rest = value;
    while (rest >= 10) {
        rest /= 10;
        digits += 1;
    }
    return digits;
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        try writer.writeByte(' ');
    }
}

fn sortForumsByLastPostDate(forums: []bgg_model.Forum) void {
    std.mem.sort(bgg_model.Forum, forums, {}, forumLastPostDesc);
}

fn forumLastPostDesc(_: void, lhs: bgg_model.Forum, rhs: bgg_model.Forum) bool {
    const order = std.mem.order(u8, lhs.last_post_date, rhs.last_post_date);
    if (order == .eq) return lhs.id < rhs.id;
    return order == .gt;
}

test "forum labels include activity summary" {
    const forums = [_]bgg_model.Forum{
        .{ .id = 1, .title = "Rules", .num_threads = 3, .num_posts = 9, .last_post_date = "2026-01-02" },
    };
    const labels = try buildForumLabels(std.testing.allocator, &forums);
    defer freeLabels(std.testing.allocator, labels);

    try std.testing.expectEqual(@as(usize, 1), labels.len);
    try std.testing.expect(std.mem.indexOf(u8, labels[0], "Rules") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels[0], "3 threads") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels[0], "2026-01-02") != null);
}

test "forum labels align title and thread count columns" {
    const forums = [_]bgg_model.Forum{
        .{ .id = 1, .title = "Rules", .num_threads = 3 },
        .{ .id = 2, .title = "Variants and Strategy", .num_threads = 12 },
    };
    const labels = try buildForumLabels(std.testing.allocator, &forums);
    defer freeLabels(std.testing.allocator, labels);

    try std.testing.expectEqualStrings("Rules                   3 threads", labels[0]);
    try std.testing.expectEqualStrings("Variants and Strategy  12 threads", labels[1]);
}

test "thread labels keep list items to subjects" {
    const threads = [_]bgg_model.ThreadSummary{
        .{ .id = 1, .subject = "Rules question", .author = "hiro", .num_articles = 2 },
    };
    const labels = try buildThreadLabels(std.testing.allocator, &threads);
    defer freeLabels(std.testing.allocator, labels);

    try std.testing.expectEqualStrings("Rules question", labels[0]);
}

test "state opens thread list without dropping forum list" {
    var state: State = .{};
    const forums = try std.testing.allocator.dupe(bgg_model.Forum, &.{
        .{ .id = 10, .title = try std.testing.allocator.dupe(u8, "Rules") },
        .{ .id = 20, .title = try std.testing.allocator.dupe(u8, "Strategy") },
    });
    defer state.deinit(std.testing.allocator);

    try state.startForumLoad(std.testing.allocator, 13, "Catan");
    try state.setForumsLoaded(std.testing.allocator, forums);
    state.startThreadLoad(std.testing.allocator, 1);

    try std.testing.expectEqual(Mode.thread_list, state.mode);
    try std.testing.expectEqual(@as(usize, 2), state.forums.len);
    try std.testing.expectEqual(@as(u32, 20), state.selectedForum().?.id);
}
