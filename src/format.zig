const std = @import("std");

const model = @import("bgg/model.zig");

/// User-facing date formats supported by bgg-tui settings and display helpers.
pub const DateFormat = enum {
    yyyy_mm_dd,
    yyyy_slash_mm_slash_dd,
    relative,
};

/// Calendar date without time zone information.
pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,
};

pub const DateFormatError = error{
    InvalidBggDate,
    InvalidDateFormat,
};

/// Controls display-width wrapping.
///
/// Width is measured in terminal cells, not bytes. The two indents are written
/// as-is and count toward the available width on their respective lines.
pub const WrapOptions = struct {
    width: usize,
    first_indent: []const u8 = "",
    subsequent_indent: []const u8 = "",
};

/// Returns the approximate terminal cell width for UTF-8 text.
///
/// This is intentionally small and app-local. It handles ASCII, combining marks,
/// common wide CJK ranges, and emoji ranges well enough for bgg-tui list/detail
/// text, but it is not a full Unicode grapheme width implementation.
pub fn displayWidth(text: []const u8) usize {
    const view = std.unicode.Utf8View.init(text) catch return text.len;
    var iter = view.iterator();

    var width: usize = 0;
    while (iter.nextCodepoint()) |codepoint| {
        width += codepointDisplayWidth(codepoint);
    }
    return width;
}

/// Writes text truncated to `max_width` terminal cells, appending `ellipsis`
/// when truncation is needed.
///
/// The output never splits a valid UTF-8 codepoint. Invalid UTF-8 falls back to
/// byte-oriented fitting.
pub fn writeTruncated(writer: *std.Io.Writer, text: []const u8, max_width: usize, ellipsis: []const u8) std.Io.Writer.Error!void {
    if (max_width == 0) return;
    if (displayWidth(text) <= max_width) {
        try writer.writeAll(text);
        return;
    }

    const ellipsis_width = displayWidth(ellipsis);
    if (ellipsis_width >= max_width) {
        try writeFitting(writer, ellipsis, max_width);
        return;
    }

    try writeFitting(writer, text, max_width - ellipsis_width);
    try writer.writeAll(ellipsis);
}

/// Writes text wrapped to `options.width` terminal cells.
///
/// Inline whitespace is collapsed, explicit `\n` is preserved, and words longer
/// than the available width are split at UTF-8 codepoint boundaries.
pub fn writeWrapped(writer: *std.Io.Writer, text: []const u8, options: WrapOptions) std.Io.Writer.Error!void {
    if (options.width == 0) return;

    var state = WrapState{
        .writer = writer,
        .width = options.width,
        .first_indent = options.first_indent,
        .subsequent_indent = options.subsequent_indent,
    };

    var index: usize = 0;
    while (index < text.len) {
        const byte = text[index];
        if (byte == '\n') {
            try state.newline();
            index += 1;
            continue;
        }
        if (isInlineWhitespace(byte)) {
            index += 1;
            continue;
        }

        const start = index;
        while (index < text.len and text[index] != '\n' and !isInlineWhitespace(text[index])) {
            index += 1;
        }
        try state.writeWord(text[start..index]);
    }
}

/// Writes `label: text` and wraps continuation lines under the value column.
pub fn writeLabeledWrapped(writer: *std.Io.Writer, label: []const u8, text: []const u8, width: usize) std.Io.Writer.Error!void {
    if (width == 0) return;

    const prefix_width = displayWidth(label) + 2;
    try writer.writeAll(label);
    try writer.writeAll(": ");

    var state = WrapState{
        .writer = writer,
        .width = width,
        .first_indent = "",
        .subsequent_indent = "",
        .line_started = true,
        .line_width = prefix_width,
        .current_indent_width = prefix_width,
        .first_line = false,
        .continuation_spaces = prefix_width,
    };

    var index: usize = 0;
    while (index < text.len) {
        const byte = text[index];
        if (byte == '\n') {
            try state.newline();
            index += 1;
            continue;
        }
        if (isInlineWhitespace(byte)) {
            index += 1;
            continue;
        }

        const start = index;
        while (index < text.len and text[index] != '\n' and !isInlineWhitespace(text[index])) {
            index += 1;
        }
        try state.writeWord(text[start..index]);
    }
}

/// Writes an unsigned integer without grouping.
pub fn writeUnsigned(writer: *std.Io.Writer, value: u64) std.Io.Writer.Error!void {
    try writer.print("{d}", .{value});
}

/// Writes an unsigned integer with comma grouping.
pub fn writeUnsignedGrouped(writer: *std.Io.Writer, value: u64) std.Io.Writer.Error!void {
    var digits: [20]u8 = undefined;
    const raw = std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable;

    for (raw, 0..) |digit, index| {
        if (index != 0 and (raw.len - index) % 3 == 0) {
            try writer.writeByte(',');
        }
        try writer.writeByte(digit);
    }
}

/// Writes a fixed decimal value for the small precision set used by the UI.
///
/// Supported precisions are 0 through 3. Other values fall back to Zig's default
/// float formatting.
pub fn writeFixedDecimal(writer: *std.Io.Writer, value: f64, precision: usize) std.Io.Writer.Error!void {
    switch (precision) {
        0 => try writer.print("{d:.0}", .{value}),
        1 => try writer.print("{d:.1}", .{value}),
        2 => try writer.print("{d:.2}", .{value}),
        3 => try writer.print("{d:.3}", .{value}),
        else => try writer.print("{d}", .{value}),
    }
}

/// Writes a BGG rating with one decimal place, or `-` for missing values.
pub fn writeOptionalRating(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value <= 0) {
        try writer.writeByte('-');
        return;
    }

    try writeFixedDecimal(writer, value, 1);
}

/// Writes a BGG weight with two decimal places, or `-` for missing values.
pub fn writeOptionalWeight(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value <= 0) {
        try writer.writeByte('-');
        return;
    }

    try writeFixedDecimal(writer, value, 2);
}

/// Writes a BGG rank as `#1,234`, or `-` for unranked values.
pub fn writeOptionalRank(writer: *std.Io.Writer, rank: u32) std.Io.Writer.Error!void {
    if (rank == 0) {
        try writer.writeByte('-');
        return;
    }

    try writer.writeByte('#');
    try writeUnsignedGrouped(writer, rank);
}

/// Writes the compact stats line used by list/detail views.
pub fn writeGameStats(writer: *std.Io.Writer, game: model.Game) std.Io.Writer.Error!void {
    try writer.writeAll("Rating ");
    try writeOptionalRating(writer, game.rating);
    try writer.writeAll(" | Geek ");
    try writeOptionalRating(writer, game.bayes_average);
    try writer.writeAll(" | Rank ");
    try writeOptionalRank(writer, game.rank);
    try writer.writeAll(" | Weight ");
    try writeOptionalWeight(writer, game.weight);
}

/// Writes player count, play time, and minimum age as one compact line.
pub fn writePlayerSummary(writer: *std.Io.Writer, game: model.Game) std.Io.Writer.Error!void {
    if (game.min_players == 0 and game.max_players == 0) {
        try writer.writeByte('-');
    } else if (game.min_players == game.max_players) {
        try writer.print("{d} players", .{game.min_players});
    } else {
        try writer.print("{d}-{d} players", .{ game.min_players, game.max_players });
    }

    if (game.playing_time > 0) {
        try writer.print(" | {d} min", .{game.playing_time});
    }
    if (game.min_age > 0) {
        try writer.print(" | age {d}+", .{game.min_age});
    }
}

/// Writes the parsed BGG suggested player count poll summary.
///
/// `best_with` and `recommended_with` are expected to already be display-ready
/// strings from the XML parser.
pub fn writePlayerCountPollSummary(writer: *std.Io.Writer, poll: model.PlayerCountPoll) std.Io.Writer.Error!void {
    var wrote = false;
    if (poll.best_with) |best_with| {
        if (best_with.len > 0) {
            try writer.writeAll(best_with);
            wrote = true;
        }
    }
    if (poll.recommended_with) |recommended_with| {
        if (recommended_with.len > 0) {
            if (wrote) try writer.writeAll(" | ");
            try writer.writeAll(recommended_with);
            wrote = true;
        }
    }
    if (poll.total_votes > 0) {
        if (wrote) try writer.writeAll(" | ");
        try writeUnsignedGrouped(writer, poll.total_votes);
        try writer.writeAll(" votes");
        wrote = true;
    }
    if (!wrote) try writer.writeByte('-');
}

/// Writes collection status flags as comma-separated labels, or `-` if none are set.
pub fn writeCollectionStatuses(writer: *std.Io.Writer, item: model.CollectionItem) std.Io.Writer.Error!void {
    var count: usize = 0;
    try writeStatusIf(writer, &count, item.owned, "Owned");
    try writeStatusIf(writer, &count, item.prev_owned, "Prev owned");
    try writeStatusIf(writer, &count, item.for_trade, "For trade");
    try writeStatusIf(writer, &count, item.want, "Want");
    try writeStatusIf(writer, &count, item.want_to_play, "Want to play");
    try writeStatusIf(writer, &count, item.want_to_buy, "Want to buy");
    try writeStatusIf(writer, &count, item.wishlist, "Wishlist");
    try writeStatusIf(writer, &count, item.preordered, "Preordered");
    if (count == 0) try writer.writeByte('-');
}

/// Writes the canonical BGG game page URL for a board game id.
pub fn writeBggGameUrl(writer: *std.Io.Writer, game_id: u32) std.Io.Writer.Error!void {
    try writer.print("https://boardgamegeek.com/boardgame/{d}", .{game_id});
}

/// Parses a config string into a supported date format.
pub fn dateFormatFromConfig(value: []const u8) DateFormatError!DateFormat {
    if (std.mem.eql(u8, value, "yyyy-mm-dd") or std.mem.eql(u8, value, "YYYY-MM-DD")) return .yyyy_mm_dd;
    if (std.mem.eql(u8, value, "yyyy/mm/dd")) return .yyyy_slash_mm_slash_dd;
    if (std.mem.eql(u8, value, "relative")) return .relative;
    return error.InvalidDateFormat;
}

/// Parses BGG's RFC-style date strings, ignoring the time and offset portion.
///
/// Example input: `Sat, 01 Jan 2025 10:00:00 +0000`.
pub fn parseBggDate(value: []const u8) DateFormatError!Date {
    if (value.len < "Sat, 01 Jan 2025".len) return error.InvalidBggDate;
    if (value.len < 16 or value[3] != ',' or value[4] != ' ') return error.InvalidBggDate;

    const day = try parseFixedU8(value[5..7]);
    if (value[7] != ' ') return error.InvalidBggDate;

    const month = try parseMonth(value[8..11]);
    if (value[11] != ' ') return error.InvalidBggDate;

    const year = std.fmt.parseInt(i32, value[12..16], 10) catch return error.InvalidBggDate;
    return validateDate(.{ .year = year, .month = month, .day = day });
}

/// Parses and writes a BGG date string in the requested display format.
pub fn writeBggDate(writer: *std.Io.Writer, value: []const u8, format: DateFormat, today: ?Date) (DateFormatError || std.Io.Writer.Error)!void {
    const date = try parseBggDate(value);
    try writeDate(writer, date, format, today);
}

/// Writes a validated date using a configured display format.
///
/// For `.relative`, `today` controls the relative base date. If no base date is
/// supplied, the function falls back to `yyyy-mm-dd`.
pub fn writeDate(writer: *std.Io.Writer, date: Date, format: DateFormat, today: ?Date) (DateFormatError || std.Io.Writer.Error)!void {
    const validated = try validateDate(date);
    switch (format) {
        .yyyy_mm_dd => try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ dateYearForDisplay(validated), validated.month, validated.day }),
        .yyyy_slash_mm_slash_dd => try writer.print("{d:0>4}/{d:0>2}/{d:0>2}", .{ dateYearForDisplay(validated), validated.month, validated.day }),
        .relative => if (today) |base|
            try writeRelativeDate(writer, validated, try validateDate(base))
        else
            try writeDate(writer, validated, .yyyy_mm_dd, null),
    }
}

fn writeRelativeDate(writer: *std.Io.Writer, date: Date, today: Date) std.Io.Writer.Error!void {
    const delta = daysFromCivil(date) - daysFromCivil(today);
    if (delta == 0) {
        try writer.writeAll("today");
    } else if (delta == -1) {
        try writer.writeAll("yesterday");
    } else if (delta < 0) {
        try writer.print("{d} days ago", .{-delta});
    } else if (delta == 1) {
        try writer.writeAll("tomorrow");
    } else {
        try writer.print("in {d} days", .{delta});
    }
}

fn parseFixedU8(value: []const u8) DateFormatError!u8 {
    if (value.len != 2) return error.InvalidBggDate;
    return std.fmt.parseInt(u8, value, 10) catch error.InvalidBggDate;
}

fn parseMonth(value: []const u8) DateFormatError!u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (months, 1..) |month, index| {
        if (std.mem.eql(u8, value, month)) return @intCast(index);
    }
    return error.InvalidBggDate;
}

fn validateDate(date: Date) DateFormatError!Date {
    if (date.year < 0) return error.InvalidBggDate;
    if (date.month < 1 or date.month > 12) return error.InvalidBggDate;
    const max_day = daysInMonth(date.year, date.month);
    if (date.day < 1 or date.day > max_day) return error.InvalidBggDate;
    return date;
}

fn dateYearForDisplay(date: Date) u32 {
    return @intCast(date.year);
}

fn daysInMonth(year: i32, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => unreachable,
    };
}

fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn daysFromCivil(date: Date) i64 {
    var year = @as(i64, date.year);
    const month = @as(i64, date.month);
    const day = @as(i64, date.day);

    year -= @intFromBool(month <= 2);
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const month_prime = month + if (month > 2) @as(i64, -3) else @as(i64, 9);
    const doy = @divFloor(153 * month_prime + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn writeStatusIf(writer: *std.Io.Writer, count: *usize, enabled: bool, label: []const u8) std.Io.Writer.Error!void {
    if (!enabled) return;
    if (count.* != 0) try writer.writeAll(", ");
    try writer.writeAll(label);
    count.* += 1;
}

fn writeFitting(writer: *std.Io.Writer, text: []const u8, max_width: usize) std.Io.Writer.Error!void {
    const view = std.unicode.Utf8View.init(text) catch {
        try writer.writeAll(text[0..@min(text.len, max_width)]);
        return;
    };
    var iter = view.iterator();

    var used_width: usize = 0;
    var end_index: usize = 0;
    while (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
        const width = codepointDisplayWidth(codepoint);
        if (used_width + width > max_width) break;

        used_width += width;
        end_index = iter.i;
    }

    try writer.writeAll(text[0..end_index]);
}

const WrapState = struct {
    writer: *std.Io.Writer,
    width: usize,
    first_indent: []const u8,
    subsequent_indent: []const u8,
    line_started: bool = false,
    line_width: usize = 0,
    current_indent_width: usize = 0,
    first_line: bool = true,
    continuation_spaces: usize = 0,

    fn writeWord(state: *WrapState, word: []const u8) std.Io.Writer.Error!void {
        if (!state.line_started) try state.startLine();

        const word_width = displayWidth(word);
        if (state.line_width > state.current_indent_width and state.line_width + 1 + word_width <= state.width) {
            try state.writer.writeByte(' ');
            state.line_width += 1;
            try state.writer.writeAll(word);
            state.line_width += word_width;
            return;
        }

        if (state.line_width > state.current_indent_width) {
            try state.newline();
            try state.startLine();
        }

        if (state.line_width + word_width <= state.width) {
            try state.writer.writeAll(word);
            state.line_width += word_width;
            return;
        }

        try state.writeLongWord(word);
    }

    fn writeLongWord(state: *WrapState, word: []const u8) std.Io.Writer.Error!void {
        var rest = word;
        while (rest.len > 0) {
            if (!state.line_started) try state.startLine();
            const available = if (state.width > state.line_width) state.width - state.line_width else 0;
            const fitting = fittingPrefix(rest, available);
            const take_len = if (fitting.byte_len > 0) fitting.byte_len else firstCodepointLen(rest);

            try state.writer.writeAll(rest[0..take_len]);
            state.line_width += if (fitting.byte_len > 0) fitting.width else displayWidth(rest[0..take_len]);
            rest = rest[take_len..];

            if (rest.len > 0) {
                try state.newline();
            }
        }
    }

    fn startLine(state: *WrapState) std.Io.Writer.Error!void {
        const use_first_indent = state.first_line;
        const indent = if (use_first_indent) state.first_indent else state.subsequent_indent;
        try state.writer.writeAll(indent);
        state.line_width = displayWidth(indent);
        if (!use_first_indent and indent.len == 0 and state.continuation_spaces > 0) {
            try writeSpaces(state.writer, state.continuation_spaces);
            state.line_width = state.continuation_spaces;
        }
        state.current_indent_width = state.line_width;
        state.line_started = true;
        state.first_line = false;
    }

    fn newline(state: *WrapState) std.Io.Writer.Error!void {
        try state.writer.writeByte('\n');
        state.line_started = false;
        state.line_width = 0;
        state.current_indent_width = 0;
    }
};

fn isInlineWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r';
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) std.Io.Writer.Error!void {
    for (0..count) |_| {
        try writer.writeByte(' ');
    }
}

fn firstCodepointLen(text: []const u8) usize {
    if (text.len == 0) return 0;
    const len = std.unicode.utf8ByteSequenceLength(text[0]) catch return 1;
    return @min(@as(usize, len), text.len);
}

fn fittingPrefix(text: []const u8, max_width: usize) struct { byte_len: usize, width: usize } {
    const view = std.unicode.Utf8View.init(text) catch return .{
        .byte_len = @min(text.len, max_width),
        .width = @min(text.len, max_width),
    };
    var iter = view.iterator();

    var used_width: usize = 0;
    var end_index: usize = 0;
    while (iter.nextCodepointSlice()) |slice| {
        const codepoint = std.unicode.utf8Decode(slice) catch unreachable;
        const width = codepointDisplayWidth(codepoint);
        if (used_width + width > max_width) break;

        used_width += width;
        end_index = iter.i;
    }

    return .{ .byte_len = end_index, .width = used_width };
}

fn codepointDisplayWidth(codepoint: u21) usize {
    if (codepoint == 0) return 0;
    if (codepoint < 0x20 or (codepoint >= 0x7f and codepoint < 0xa0)) return 0;
    if (isCombiningCodepoint(codepoint)) return 0;
    if (isWideCodepoint(codepoint)) return 2;
    return 1;
}

fn isCombiningCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f);
}

fn isWideCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x115f) or
        (codepoint >= 0x2329 and codepoint <= 0x232a) or
        (codepoint >= 0x2e80 and codepoint <= 0xa4cf) or
        (codepoint >= 0xac00 and codepoint <= 0xd7a3) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0xfe10 and codepoint <= 0xfe19) or
        (codepoint >= 0xfe30 and codepoint <= 0xfe6f) or
        (codepoint >= 0xff00 and codepoint <= 0xff60) or
        (codepoint >= 0xffe0 and codepoint <= 0xffe6) or
        (codepoint >= 0x1f300 and codepoint <= 0x1faff) or
        (codepoint >= 0x20000 and codepoint <= 0x3fffd);
}

fn expectFormatted(expected: []const u8, write_fn: anytype, args: anytype) !void {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    try @call(.auto, write_fn, .{&out.writer} ++ args);

    const actual = try out.toOwnedSlice();
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}

test "format unsigned values" {
    try expectFormatted("0", writeUnsigned, .{@as(u64, 0)});
    try expectFormatted("1234567", writeUnsigned, .{@as(u64, 1_234_567)});
}

test "format grouped unsigned values" {
    try expectFormatted("0", writeUnsignedGrouped, .{@as(u64, 0)});
    try expectFormatted("999", writeUnsignedGrouped, .{@as(u64, 999)});
    try expectFormatted("1,000", writeUnsignedGrouped, .{@as(u64, 1_000)});
    try expectFormatted("1,234,567", writeUnsignedGrouped, .{@as(u64, 1_234_567)});
}

test "format fixed decimal values" {
    try expectFormatted("7.1", writeFixedDecimal, .{ @as(f64, 7.145), @as(usize, 1) });
    try expectFormatted("2.32", writeFixedDecimal, .{ @as(f64, 2.321), @as(usize, 2) });
}

test "format optional rating and weight values" {
    try expectFormatted("-", writeOptionalRating, .{@as(f64, 0)});
    try expectFormatted("7.1", writeOptionalRating, .{@as(f64, 7.14)});
    try expectFormatted("-", writeOptionalWeight, .{@as(f64, 0)});
    try expectFormatted("2.32", writeOptionalWeight, .{@as(f64, 2.321)});
}

test "format optional rank values" {
    try expectFormatted("-", writeOptionalRank, .{@as(u32, 0)});
    try expectFormatted("#389", writeOptionalRank, .{@as(u32, 389)});
    try expectFormatted("#1,234", writeOptionalRank, .{@as(u32, 1_234)});
}

test "format game stats summary" {
    const game = model.Game{
        .id = 13,
        .name = "CATAN",
        .rating = 7.145,
        .bayes_average = 7.012,
        .rank = 389,
        .weight = 2.321,
    };

    try expectFormatted("Rating 7.1 | Geek 7.0 | Rank #389 | Weight 2.32", writeGameStats, .{game});
}

test "format missing game stats as dashes" {
    const game = model.Game{ .id = 1, .name = "Unranked" };

    try expectFormatted("Rating - | Geek - | Rank - | Weight -", writeGameStats, .{game});
}

test "format player summary" {
    try expectFormatted(
        "3-4 players | 120 min | age 10+",
        writePlayerSummary,
        .{model.Game{ .id = 13, .name = "CATAN", .min_players = 3, .max_players = 4, .playing_time = 120, .min_age = 10 }},
    );
    try expectFormatted(
        "2 players",
        writePlayerSummary,
        .{model.Game{ .id = 1, .name = "Duel", .min_players = 2, .max_players = 2 }},
    );
    try expectFormatted(
        "-",
        writePlayerSummary,
        .{model.Game{ .id = 2, .name = "Unknown" }},
    );
}

test "format player count poll summary" {
    try expectFormatted(
        "Best with 4 players | Recommended with 3-4 players | 2,551 votes",
        writePlayerCountPollSummary,
        .{model.PlayerCountPoll{
            .total_votes = 2_551,
            .best_with = "Best with 4 players",
            .recommended_with = "Recommended with 3-4 players",
        }},
    );
    try expectFormatted("-", writePlayerCountPollSummary, .{model.PlayerCountPoll{}});
}

test "format collection statuses" {
    try expectFormatted(
        "Owned, Want to play, Wishlist",
        writeCollectionStatuses,
        .{model.CollectionItem{ .id = 13, .name = "CATAN", .owned = true, .want_to_play = true, .wishlist = true }},
    );
    try expectFormatted("-", writeCollectionStatuses, .{model.CollectionItem{ .id = 1, .name = "No Status" }});
}

test "format bgg game url" {
    try expectFormatted("https://boardgamegeek.com/boardgame/13", writeBggGameUrl, .{@as(u32, 13)});
}

test "calculate display width for ascii and common wide text" {
    try std.testing.expectEqual(@as(usize, 5), displayWidth("Catan"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("あ"));
    try std.testing.expectEqual(@as(usize, 6), displayWidth("あいう"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("e\u{301}"));
}

test "truncate text by display width" {
    try expectFormatted("Catan", writeTruncated, .{ "Catan", @as(usize, 10), "..." });
    try expectFormatted("Cat...", writeTruncated, .{ "Catan: Seafarers", @as(usize, 6), "..." });
    try expectFormatted("...", writeTruncated, .{ "Catan", @as(usize, 3), "..." });
    try expectFormatted(".", writeTruncated, .{ "Catan", @as(usize, 1), "..." });
}

test "truncate wide text without splitting utf-8 codepoints" {
    try expectFormatted("あ...", writeTruncated, .{ "あいう", @as(usize, 5), "..." });
    try expectFormatted("...", writeTruncated, .{ "あいう", @as(usize, 4), "..." });
}

test "wrap text by display width" {
    try expectFormatted(
        "Teach rules\nbefore setup",
        writeWrapped,
        .{ "Teach rules before setup", WrapOptions{ .width = 12 } },
    );
    try expectFormatted(
        "  Teach\n  rules",
        writeWrapped,
        .{ "Teach rules", WrapOptions{ .width = 8, .first_indent = "  ", .subsequent_indent = "  " } },
    );
    try expectFormatted(
        "short\n\nnext",
        writeWrapped,
        .{ "short\n\nnext", WrapOptions{ .width = 20 } },
    );
}

test "wrap long words without splitting utf-8 codepoints" {
    try expectFormatted(
        "super\ncalif\nragil\nistic",
        writeWrapped,
        .{ "supercalifragilistic", WrapOptions{ .width = 5 } },
    );
    try expectFormatted(
        "あい\nう",
        writeWrapped,
        .{ "あいう", WrapOptions{ .width = 4 } },
    );
}

test "wrap labeled text with aligned continuation lines" {
    try expectFormatted(
        "Players: 2-4\n         best",
        writeLabeledWrapped,
        .{ "Players", "2-4 best", @as(usize, 14) },
    );
}

test "parse date format config values" {
    try std.testing.expectEqual(DateFormat.yyyy_mm_dd, try dateFormatFromConfig("yyyy-mm-dd"));
    try std.testing.expectEqual(DateFormat.yyyy_mm_dd, try dateFormatFromConfig("YYYY-MM-DD"));
    try std.testing.expectEqual(DateFormat.yyyy_slash_mm_slash_dd, try dateFormatFromConfig("yyyy/mm/dd"));
    try std.testing.expectEqual(DateFormat.relative, try dateFormatFromConfig("relative"));
    try std.testing.expectError(error.InvalidDateFormat, dateFormatFromConfig("mm/dd/yyyy"));
}

test "parse bgg rfc-style date values" {
    const date = try parseBggDate("Sat, 01 Jan 2025 10:00:00 +0000");

    try std.testing.expectEqual(@as(i32, 2025), date.year);
    try std.testing.expectEqual(@as(u8, 1), date.month);
    try std.testing.expectEqual(@as(u8, 1), date.day);

    try std.testing.expectError(error.InvalidBggDate, parseBggDate(""));
    try std.testing.expectError(error.InvalidBggDate, parseBggDate("Sat, 32 Jan 2025 10:00:00 +0000"));
    try std.testing.expectError(error.InvalidBggDate, parseBggDate("Sat, 29 Feb 2025 10:00:00 +0000"));
}

test "format bgg dates as absolute dates" {
    const bgg_date = "Sat, 01 Jan 2025 10:00:00 +0000";

    try expectFormatted("2025-01-01", writeBggDate, .{ bgg_date, DateFormat.yyyy_mm_dd, @as(?Date, null) });
    try expectFormatted("2025/01/01", writeBggDate, .{ bgg_date, DateFormat.yyyy_slash_mm_slash_dd, @as(?Date, null) });
}

test "format bgg dates as relative dates" {
    const today = Date{ .year = 2025, .month = 1, .day = 1 };

    try expectFormatted("today", writeBggDate, .{ "Sat, 01 Jan 2025 10:00:00 +0000", DateFormat.relative, @as(?Date, today) });
    try expectFormatted("yesterday", writeBggDate, .{ "Fri, 31 Dec 2024 15:30:00 +0000", DateFormat.relative, @as(?Date, today) });
    try expectFormatted("7 days ago", writeBggDate, .{ "Wed, 25 Dec 2024 08:00:00 +0000", DateFormat.relative, @as(?Date, today) });
    try expectFormatted("tomorrow", writeBggDate, .{ "Thu, 02 Jan 2025 08:00:00 +0000", DateFormat.relative, @as(?Date, today) });
    try expectFormatted("in 4 days", writeBggDate, .{ "Sun, 05 Jan 2025 08:00:00 +0000", DateFormat.relative, @as(?Date, today) });
    try expectFormatted("2025-01-01", writeBggDate, .{ "Sat, 01 Jan 2025 10:00:00 +0000", DateFormat.relative, @as(?Date, null) });
}
