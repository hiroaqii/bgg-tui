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

/// Converts a parser failure into the domain error shape used by BGG callers.
/// Allocation failures should still be returned as Zig errors by the caller;
/// this helper is for malformed or unexpected API payloads.
pub fn classifyParseError(err: anyerror) ApiError {
    return .{ .parse = .{ .message = parseErrorMessage(err) } };
}

pub fn parseErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingRequiredAttribute => "BGG API response is missing a required XML attribute",
        error.MissingName => "BGG API response is missing a required name field",
        error.MissingPrimaryName => "BGG API response is missing a primary name field",
        error.UnexpectedEndOfDocument => "BGG API response ended unexpectedly",
        error.UnexpectedElementEnd => "BGG API response closed an unexpected XML element",
        else => @errorName(err),
    };
}

test "api error kind is available without allocation" {
    const err: ApiError = .{ .not_found = .{ .id = 13 } };
    try std.testing.expectEqual(ErrorKind.not_found, err.kind());
    try std.testing.expectEqual(@as(?u32, 13), err.not_found.id);
}

test "parser errors classify as api parse errors" {
    const err = classifyParseError(error.MissingPrimaryName);

    try std.testing.expectEqual(ErrorKind.parse, err.kind());
    try std.testing.expectEqualStrings("BGG API response is missing a primary name field", err.parse.message);
}

test "unknown parser errors keep their error name" {
    const err = classifyParseError(error.InvalidXml);

    try std.testing.expectEqual(ErrorKind.parse, err.kind());
    try std.testing.expectEqualStrings("InvalidXml", err.parse.message);
}
