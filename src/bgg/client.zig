const std = @import("std");

const endpoint = @import("endpoint.zig");
const api_error = @import("error.zig");

const Allocator = std.mem.Allocator;

pub const Options = struct {
    base_url: []const u8 = endpoint.base_url,
    token: ?[]const u8 = null,
    // Prevents accidental unbounded allocation when BGG returns an unexpectedly
    // large response body.
    max_response_bytes: usize = 8 * 1024 * 1024,
    retry: RetryOptions = .{},
};

pub const RetryOptions = struct {
    max_attempts: u8 = 3,
    base_delay_ms: u64 = 500,
    max_delay_ms: u64 = 10_000,
    collection_accepted_max_attempts: u8 = endpoint.collection_max_retries,
};

pub const EndpointKind = enum {
    generic,
    collection,
};

pub const Response = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(response: Response, allocator: Allocator) void {
        allocator.free(response.body);
    }
};

pub const RequestResult = union(enum) {
    ok: Response,
    api_error: api_error.ApiError,
};

pub const Client = struct {
    allocator: Allocator,
    http: std.http.Client,
    options: Options,

    pub fn init(allocator: Allocator, options: Options) Client {
        return .{
            .allocator = allocator,
            .http = .{ .allocator = allocator },
            .options = options,
        };
    }

    pub fn deinit(client: *Client) void {
        client.http.deinit();
    }

    pub fn buildUrl(client: *Client, path: []const u8) ![]u8 {
        return try joinBaseUrl(client.allocator, client.options.base_url, path);
    }

    pub fn getPath(client: *Client, path: []const u8, endpoint_kind: EndpointKind) !RequestResult {
        const url = try client.buildUrl(path);
        defer client.allocator.free(url);

        // Authorization is a privileged header so std.http strips it if a
        // redirect crosses to another host.
        var auth_value: ?[]u8 = null;
        defer if (auth_value) |value| client.allocator.free(value);

        const token = client.options.token orelse return .{ .api_error = missingTokenError() };
        if (token.len == 0) return .{ .api_error = missingTokenError() };

        var headers_buf: [1]std.http.Header = undefined;
        auth_value = try authorizationValue(client.allocator, token);
        headers_buf[0] = .{ .name = "authorization", .value = auth_value.? };
        const privileged_headers: []const std.http.Header = headers_buf[0..1];

        var attempt: u8 = 0;
        while (true) : (attempt += 1) {
            const uri = std.Uri.parse(url) catch |parse_error| {
                return .{ .api_error = .{ .network = .{ .message = @errorName(parse_error) } } };
            };

            var request = client.http.request(.GET, uri, .{
                .privileged_headers = privileged_headers,
            }) catch |request_error| {
                return .{ .api_error = .{ .network = .{ .message = @errorName(request_error) } } };
            };
            defer request.deinit();

            request.sendBodiless() catch |send_error| {
                return .{ .api_error = .{ .network = .{ .message = @errorName(send_error) } } };
            };

            var redirect_buffer: [8 * 1024]u8 = undefined;
            var http_response = request.receiveHead(&redirect_buffer) catch |receive_error| {
                return .{ .api_error = .{ .network = .{ .message = @errorName(receive_error) } } };
            };

            const status = http_response.head.status;
            const retry_after_seconds = retryAfterSecondsFromHead(http_response.head);

            // BGG uses 202 for collection requests while server-side processing
            // is still in progress. Other endpoints treat it as a normal 2xx.
            if (shouldRetryStatus(status, attempt, client.options.retry, endpoint_kind)) {
                discardResponseBody(&http_response);
                std.Thread.sleep(retryDelayMs(attempt, client.options.retry, retry_after_seconds) * std.time.ns_per_ms);
                continue;
            }

            if (status == .accepted and endpoint_kind == .collection) {
                discardResponseBody(&http_response);
                return .{ .api_error = .{ .network = .{
                    .message = "BGG collection is still processing",
                    .status_code = @intFromEnum(status),
                } } };
            }

            if (classifyStatus(status, retry_after_seconds)) |err| {
                discardResponseBody(&http_response);
                return .{ .api_error = err };
            }

            const body = readResponseBody(client, &http_response) catch |read_error| switch (read_error) {
                error.OutOfMemory => return error.OutOfMemory,
                error.StreamTooLong => return .{ .api_error = .{ .network = .{
                    .message = "BGG API response exceeded the configured body size limit",
                    .status_code = @intFromEnum(status),
                } } },
                else => return .{ .api_error = .{ .network = .{
                    .message = @errorName(read_error),
                    .status_code = @intFromEnum(status),
                } } },
            };

            return .{ .ok = .{
                .status = status,
                .body = body,
            } };
        }
    }
};

/// Joins an absolute base URL and an API path without producing duplicate or
/// missing slashes.
pub fn joinBaseUrl(allocator: Allocator, base_url: []const u8, path: []const u8) ![]u8 {
    if (base_url.len == 0) return allocator.dupe(u8, path);
    if (path.len == 0) return allocator.dupe(u8, base_url);

    if (base_url[base_url.len - 1] == '/' and path[0] == '/') {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_url[0 .. base_url.len - 1], path });
    }
    if (base_url[base_url.len - 1] != '/' and path[0] != '/') {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base_url, path });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_url, path });
}

pub fn authorizationValue(allocator: Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
}

fn missingTokenError() api_error.ApiError {
    return .{ .auth = .{ .message = "BGG API token is required" } };
}

/// Converts protocol-level HTTP statuses into the domain error shape used by
/// callers. Retry decisions stay separate so they can happen before this step.
pub fn classifyStatus(status: std.http.Status, retry_after_seconds: ?u64) ?api_error.ApiError {
    return switch (status) {
        .ok, .accepted => null,
        .unauthorized, .forbidden => .{ .auth = .{ .message = "BGG API authentication failed" } },
        .not_found => .{ .not_found = .{} },
        .too_many_requests => .{ .rate_limit = .{
            .message = "BGG API rate limit exceeded",
            .retry_after_seconds = retry_after_seconds orelse 0,
        } },
        else => {
            const code = @intFromEnum(status);
            if (code >= 200 and code < 300) return null;
            return .{ .network = .{
                .message = "BGG API returned an unexpected HTTP status",
                .status_code = code,
            } };
        },
    };
}

pub fn shouldRetryStatus(status: std.http.Status, attempt: u8, options: RetryOptions, endpoint_kind: EndpointKind) bool {
    if (endpoint_kind == .collection and status == .accepted) {
        return attempt + 1 < options.collection_accepted_max_attempts;
    }

    const code = @intFromEnum(status);
    if (status == .too_many_requests or code >= 500) {
        return attempt + 1 < options.max_attempts;
    }

    return false;
}

pub fn retryDelayMs(attempt: u8, options: RetryOptions, retry_after_seconds: ?u64) u64 {
    if (retry_after_seconds) |seconds| {
        const max_seconds = options.max_delay_ms / std.time.ms_per_s;
        const clamped_seconds = @min(seconds, max_seconds);
        const delay_ms = clamped_seconds * std.time.ms_per_s;
        return std.math.clamp(delay_ms, options.base_delay_ms, options.max_delay_ms);
    }

    const shift: std.math.Log2Int(u64) = @intCast(@min(attempt, 62));
    const delay = options.base_delay_ms << shift;
    return @min(delay, options.max_delay_ms);
}

pub fn parseRetryAfterSeconds(value: []const u8) ?u64 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(u64, trimmed, 10) catch null;
}

pub fn retryAfterSecondsFromHead(head: std.http.Client.Response.Head) ?u64 {
    var headers = head.iterateHeaders();
    while (headers.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "retry-after")) {
            return parseRetryAfterSeconds(header.value);
        }
    }
    return null;
}

fn readResponseBody(client: *Client, response: *std.http.Client.Response) ![]u8 {
    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try client.allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try client.allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (response.head.content_encoding != .identity) client.allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    return reader.allocRemaining(client.allocator, .limited(client.options.max_response_bytes)) catch |read_error| switch (read_error) {
        error.ReadFailed => return response.bodyErr() orelse error.ReadFailed,
        else => |err| return err,
    };
}

fn discardResponseBody(response: *std.http.Client.Response) void {
    var transfer_buffer: [64]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    _ = reader.discardRemaining() catch {};
}

test "client joins base URL and endpoint path" {
    const url = try joinBaseUrl(std.testing.allocator, endpoint.base_url, "/thing?id=13&stats=1");
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings("https://boardgamegeek.com/xmlapi2/thing?id=13&stats=1", url);
}

test "client builds bearer authorization value" {
    const value = try authorizationValue(std.testing.allocator, "token-123");
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings("Bearer token-123", value);
}

test "client classifies BGG API HTTP status codes" {
    try std.testing.expect(classifyStatus(.ok, null) == null);
    try std.testing.expect(classifyStatus(.accepted, null) == null);

    const auth = classifyStatus(.unauthorized, null).?;
    try std.testing.expectEqual(api_error.ErrorKind.auth, auth.kind());

    const missing = classifyStatus(.not_found, null).?;
    try std.testing.expectEqual(api_error.ErrorKind.not_found, missing.kind());

    const limited = classifyStatus(.too_many_requests, 30).?;
    try std.testing.expectEqual(api_error.ErrorKind.rate_limit, limited.kind());
    try std.testing.expectEqual(@as(u64, 30), limited.rate_limit.retry_after_seconds);

    const network = classifyStatus(.internal_server_error, null).?;
    try std.testing.expectEqual(api_error.ErrorKind.network, network.kind());
    try std.testing.expectEqual(@as(?u16, 500), network.network.status_code);
}

test "client retry policy covers collection 202 and transient HTTP failures" {
    const options: RetryOptions = .{ .max_attempts = 3, .collection_accepted_max_attempts = 10 };

    try std.testing.expect(shouldRetryStatus(.accepted, 0, options, .collection));
    try std.testing.expect(!shouldRetryStatus(.accepted, 9, options, .collection));
    try std.testing.expect(!shouldRetryStatus(.accepted, 0, options, .generic));

    try std.testing.expect(shouldRetryStatus(.too_many_requests, 1, options, .generic));
    try std.testing.expect(shouldRetryStatus(.service_unavailable, 1, options, .generic));
    try std.testing.expect(!shouldRetryStatus(.service_unavailable, 2, options, .generic));
}

test "client retry delay uses retry-after when available and otherwise backs off" {
    const options: RetryOptions = .{ .base_delay_ms = 250, .max_delay_ms = 2_000 };

    try std.testing.expectEqual(@as(u64, 250), retryDelayMs(0, options, null));
    try std.testing.expectEqual(@as(u64, 1_000), retryDelayMs(2, options, null));
    try std.testing.expectEqual(@as(u64, 2_000), retryDelayMs(4, options, null));
    try std.testing.expectEqual(@as(u64, 2_000), retryDelayMs(0, options, 10));
    try std.testing.expectEqual(@as(u64, 2_000), retryDelayMs(0, options, std.math.maxInt(u64)));
}

test "client parses numeric Retry-After header values" {
    try std.testing.expectEqual(@as(?u64, 30), parseRetryAfterSeconds(" 30\r\n"));
    try std.testing.expectEqual(@as(?u64, null), parseRetryAfterSeconds(""));
    try std.testing.expectEqual(@as(?u64, null), parseRetryAfterSeconds("Wed, 21 Oct 2015 07:28:00 GMT"));
}

test "client reads Retry-After from HTTP response headers" {
    const bytes = "HTTP/1.1 429 Too Many Requests\r\n" ++
        "Date: Sun, 17 May 2026 00:00:00 GMT\r\n" ++
        "Retry-After: 42\r\n" ++
        "Content-Length: 0\r\n\r\n";
    const head = try std.http.Client.Response.Head.parse(bytes);

    try std.testing.expectEqual(@as(?u64, 42), retryAfterSecondsFromHead(head));
}
