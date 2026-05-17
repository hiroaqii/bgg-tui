const std = @import("std");

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
