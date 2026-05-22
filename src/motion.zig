const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");

const blink_period: u64 = 90;
const wave_period: u64 = 90;
const wave_colors = [_]chasen.Color{
    .{ .rgb = .{ 0xff, 0x6b, 0x6b } },
    .{ .rgb = .{ 0xff, 0xe6, 0x6d } },
    .{ .rgb = .{ 0x4e, 0xcd, 0xc4 } },
    .{ .rgb = .{ 0x45, 0xb7, 0xd1 } },
    .{ .rgb = .{ 0x96, 0xce, 0xb4 } },
};

pub fn selectionNeedsFrame(selection: []const u8) bool {
    return std.mem.eql(u8, selection, "blink") or std.mem.eql(u8, selection, "wave");
}

pub fn focusedStyle(base: chasen.TextStyle, selection: []const u8, frame: u64) chasen.TextStyle {
    if (std.mem.eql(u8, selection, "blink")) {
        return if (anim.blink.isOn(frame, blink_period, 0.5)) base else .{};
    }
    return base;
}

pub fn drawFocusedText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, selection: []const u8, frame: u64) void {
    if (std.mem.eql(u8, selection, "wave")) {
        drawWaveText(surface, col, row, text, base, frame);
        return;
    }
    _ = surface.borrowTextAt(col, row, text, focusedStyle(base, selection, frame));
}

fn drawWaveText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, frame: u64) void {
    var cursor = col;
    var index: u32 = 0;
    var iter = chasen.text.graphemeIterator(text);
    while (iter.next()) |grapheme| : (index += 1) {
        const bytes = grapheme.bytes(text);
        var style = base;
        style.bold = true;
        style.fg = waveColor(frame, index);
        _ = surface.borrowTextAt(cursor, row, bytes, style);
        cursor +|= chasen.text.displayWidth(bytes);
    }
}

fn waveColor(frame: u64, index: u32) chasen.Color {
    const wave = std.math.sin(@as(f64, @floatFromInt(frame)) * 0.05 + @as(f64, @floatFromInt(index)) * 0.3);
    const scaled = (wave + 1.0) / 2.0 * @as(f64, @floatFromInt(wave_colors.len - 1));
    const color_index: usize = @intFromFloat(@floor(scaled));
    return wave_colors[@min(color_index, wave_colors.len - 1)];
}

test "blink selection requests frames" {
    try std.testing.expect(selectionNeedsFrame("blink"));
    try std.testing.expect(!selectionNeedsFrame("none"));
    try std.testing.expect(selectionNeedsFrame("wave"));
}

test "blink focused style alternates without changing layout" {
    const base: chasen.TextStyle = .{ .bold = true, .fg = .{ .index = 14 } };
    try std.testing.expectEqual(base, focusedStyle(base, "blink", 0));
    try std.testing.expectEqual(chasen.TextStyle{}, focusedStyle(base, "blink", 45));
    try std.testing.expectEqual(base, focusedStyle(base, "none", 15));
}

test "wave focused style remains base because color is drawn per grapheme" {
    const base: chasen.TextStyle = .{ .bold = true, .fg = .{ .index = 14 } };
    try std.testing.expectEqual(base, focusedStyle(base, "wave", 0));
    try std.testing.expectEqual(base, focusedStyle(base, "wave", 45));
}

test "wave color uses the Go version palette order" {
    try std.testing.expectEqual(chasen.Color{ .rgb = .{ 0x4e, 0xcd, 0xc4 } }, waveColor(0, 0));
    try std.testing.expectEqual(chasen.Color{ .rgb = .{ 0x45, 0xb7, 0xd1 } }, waveColor(0, 3));
}
