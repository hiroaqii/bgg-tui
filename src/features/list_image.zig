const std = @import("std");
const chasen = @import("chasen");

const screens = @import("../screens/root.zig");

pub const focus_settle_frames: u64 = 12;

pub const SourceKind = enum {
    hot_games,
    collection,
};

pub const Source = struct {
    kind: SourceKind,
    id: u32,
    url: []const u8,

    pub fn eql(self: Source, other: Source) bool {
        return self.kind == other.kind and
            self.id == other.id and
            std.mem.eql(u8, self.url, other.url);
    }
};

pub const State = struct {
    request_id: u64 = 0,
    source: ?Source = null,
    candidate: ?Source = null,
    candidate_start_frame: u64 = 0,
    image_state: screens.detail.ImageState = .idle,
    terminal_image_request_id: ?chasen.TerminalImageRequestId = null,
    terminal_image_handle: ?chasen.TerminalImageHandle = null,
    terminal_image_load_error: ?chasen.TerminalImageLoadError = null,
    cache_task_pending: bool = false,

    pub fn reset(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.source = null;
        self.candidate = null;
        self.candidate_start_frame = 0;
        self.cache_task_pending = false;
    }

    pub fn setSourceImmediate(self: *State, allocator: std.mem.Allocator, source: ?Source) bool {
        if (sameOptionalSource(self.source, source)) return false;
        self.clearImage(allocator);
        self.request_id +%= 1;
        self.source = source;
        self.candidate = null;
        self.candidate_start_frame = 0;
        self.cache_task_pending = false;
        return true;
    }

    pub fn setCandidate(self: *State, source: ?Source, frame: u64) bool {
        if (sameOptionalSource(self.candidate, source)) return false;
        self.candidate = source;
        self.candidate_start_frame = frame;
        return true;
    }

    pub fn candidateSettled(self: *const State, frame: u64) bool {
        return self.candidate != null and frame -| self.candidate_start_frame >= focus_settle_frames;
    }

    pub fn setImageDisabled(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .disabled;
    }

    pub fn setImageUnavailable(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .unavailable;
    }

    pub fn setImageLoading(self: *State, allocator: std.mem.Allocator) void {
        self.clearImage(allocator);
        self.image_state = .loading;
    }

    pub fn setImageCached(self: *State, allocator: std.mem.Allocator, path: []u8) void {
        self.clearImage(allocator);
        self.image_state = .{ .cached = path };
    }

    pub fn setImageFailed(self: *State, allocator: std.mem.Allocator, message: []const u8) void {
        self.clearImage(allocator);
        self.image_state = .{ .failed = message };
    }

    pub fn setTerminalImageLoading(self: *State) void {
        self.terminal_image_request_id = null;
        self.terminal_image_handle = null;
        self.terminal_image_load_error = null;
    }

    pub fn setTerminalImageLoaded(self: *State, handle: chasen.TerminalImageHandle) void {
        self.terminal_image_handle = handle;
        self.terminal_image_load_error = null;
    }

    pub fn setTerminalImageFailed(self: *State, reason: chasen.TerminalImageLoadError) void {
        self.terminal_image_handle = null;
        self.terminal_image_load_error = reason;
    }

    pub fn imagePath(self: *const State) ?[]const u8 {
        return switch (self.image_state) {
            .cached => |path| path,
            else => null,
        };
    }

    pub fn clearImage(self: *State, allocator: std.mem.Allocator) void {
        switch (self.image_state) {
            .cached => |path| allocator.free(path),
            else => {},
        }
        self.image_state = .idle;
        self.terminal_image_request_id = null;
        self.terminal_image_handle = null;
        self.terminal_image_load_error = null;
        self.cache_task_pending = false;
    }
};

pub fn sameOptionalSource(a: ?Source, b: ?Source) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.?.eql(b.?);
}

test "source equality compares kind id and url" {
    const source = Source{ .kind = .hot_games, .id = 1, .url = "a.png" };

    try std.testing.expect(source.eql(.{ .kind = .hot_games, .id = 1, .url = "a.png" }));
    try std.testing.expect(!source.eql(.{ .kind = .collection, .id = 1, .url = "a.png" }));
    try std.testing.expect(!source.eql(.{ .kind = .hot_games, .id = 2, .url = "a.png" }));
    try std.testing.expect(!source.eql(.{ .kind = .hot_games, .id = 1, .url = "b.png" }));
}

test "candidate waits for focus settle frames" {
    var state: State = .{};
    try std.testing.expect(state.setCandidate(.{ .kind = .hot_games, .id = 1, .url = "a.png" }, 10));

    try std.testing.expect(!state.candidateSettled(10 + focus_settle_frames - 1));
    try std.testing.expect(state.candidateSettled(10 + focus_settle_frames));
}
