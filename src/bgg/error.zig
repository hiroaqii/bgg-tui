const std = @import("std");

pub const ErrorKind = enum {
    auth,
    rate_limit,
    not_found,
    network,
    parse,
};

pub const ApiError = union(ErrorKind) {
    auth: AuthError,
    rate_limit: RateLimitError,
    not_found: NotFoundError,
    network: NetworkError,
    parse: ParseError,

    pub fn kind(err: ApiError) ErrorKind {
        return std.meta.activeTag(err);
    }
};

pub const AuthError = struct {
    message: []const u8,
};

pub const RateLimitError = struct {
    message: []const u8,
    retry_after_seconds: u64 = 0,
};

pub const NotFoundError = struct {
    id: ?u32 = null,
};

pub const NetworkError = struct {
    message: []const u8,
    status_code: ?u16 = null,
};

pub const ParseError = struct {
    message: []const u8,
};

test "api error kind is available without allocation" {
    const err: ApiError = .{ .not_found = .{ .id = 13 } };
    try std.testing.expectEqual(ErrorKind.not_found, err.kind());
    try std.testing.expectEqual(@as(?u32, 13), err.not_found.id);
}
