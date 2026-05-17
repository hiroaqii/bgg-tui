const std = @import("std");

pub const DateFormat = enum {
    yyyy_mm_dd,
    yyyy_slash_mm_slash_dd,
    relative,
};

pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,
};

pub const DateFormatError = error{
    InvalidBggDate,
    InvalidDateFormat,
};

pub fn writeUnsigned(writer: *std.Io.Writer, value: u64) std.Io.Writer.Error!void {
    try writer.print("{d}", .{value});
}

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

pub fn writeFixedDecimal(writer: *std.Io.Writer, value: f64, precision: usize) std.Io.Writer.Error!void {
    switch (precision) {
        0 => try writer.print("{d:.0}", .{value}),
        1 => try writer.print("{d:.1}", .{value}),
        2 => try writer.print("{d:.2}", .{value}),
        3 => try writer.print("{d:.3}", .{value}),
        else => try writer.print("{d}", .{value}),
    }
}

pub fn writeOptionalRating(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value <= 0) {
        try writer.writeByte('-');
        return;
    }

    try writeFixedDecimal(writer, value, 1);
}

pub fn writeOptionalWeight(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value <= 0) {
        try writer.writeByte('-');
        return;
    }

    try writeFixedDecimal(writer, value, 2);
}

pub fn writeOptionalRank(writer: *std.Io.Writer, rank: u32) std.Io.Writer.Error!void {
    if (rank == 0) {
        try writer.writeByte('-');
        return;
    }

    try writer.writeByte('#');
    try writeUnsignedGrouped(writer, rank);
}

pub fn dateFormatFromConfig(value: []const u8) DateFormatError!DateFormat {
    if (std.mem.eql(u8, value, "yyyy-mm-dd") or std.mem.eql(u8, value, "YYYY-MM-DD")) return .yyyy_mm_dd;
    if (std.mem.eql(u8, value, "yyyy/mm/dd")) return .yyyy_slash_mm_slash_dd;
    if (std.mem.eql(u8, value, "relative")) return .relative;
    return error.InvalidDateFormat;
}

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

pub fn writeBggDate(writer: *std.Io.Writer, value: []const u8, format: DateFormat, today: ?Date) (DateFormatError || std.Io.Writer.Error)!void {
    const date = try parseBggDate(value);
    try writeDate(writer, date, format, today);
}

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
