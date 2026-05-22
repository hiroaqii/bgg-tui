const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");

const blink_period: u64 = 90;
const wave_colors = [_]chasen.Color{
    .{ .rgb = .{ 0xff, 0x6b, 0x6b } },
    .{ .rgb = .{ 0xff, 0xe6, 0x6d } },
    .{ .rgb = .{ 0x4e, 0xcd, 0xc4 } },
    .{ .rgb = .{ 0x45, 0xb7, 0xd1 } },
    .{ .rgb = .{ 0x96, 0xce, 0xb4 } },
};
const scan_colors = [_]chasen.Color{
    .{ .rgb = .{ 0xf8, 0xf8, 0xf2 } },
    .{ .rgb = .{ 0x4e, 0xcd, 0xc4 } },
    .{ .rgb = .{ 0x45, 0xb7, 0xd1 } },
};
const glitch_chars = [_][]const u8{ "@", "#", "$", "%", "&", "*", "!", "?", "+", "=", "~", "^", "x", "X", "░", "▒", "▓", "█" };

pub fn selectionNeedsFrame(selection: []const u8) bool {
    return std.mem.eql(u8, selection, "blink") or
        std.mem.eql(u8, selection, "wave") or
        std.mem.eql(u8, selection, "glitch") or
        std.mem.eql(u8, selection, "scan");
}

pub fn focusedStyle(base: chasen.TextStyle, selection: []const u8, frame: u64) chasen.TextStyle {
    if (std.mem.eql(u8, selection, "blink")) {
        return if (anim.blink.isOn(frame, blink_period, 0.5)) base else .{};
    }
    if (std.mem.eql(u8, selection, "invert")) {
        var style = base;
        style.bold = true;
        style.reverse = true;
        return style;
    }
    return base;
}

pub fn drawFocusedText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, selection: []const u8, frame: u64) void {
    if (std.mem.eql(u8, selection, "wave")) {
        drawWaveText(surface, col, row, text, base, frame);
        return;
    }
    if (std.mem.eql(u8, selection, "scan")) {
        drawScanText(surface, col, row, text, base, frame);
        return;
    }
    if (std.mem.eql(u8, selection, "glitch")) {
        drawGlitchText(surface, col, row, text, base, frame);
        return;
    }
    _ = surface.borrowTextAt(col, row, text, focusedStyle(base, selection, frame));
}

pub fn drawStatusScanText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, frame: u64) void {
    drawScanTextWithStep(surface, col, row, text, base, frame, 3);
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
    const wave = std.math.sin(@as(f64, @floatFromInt(frame)) * 0.05 - @as(f64, @floatFromInt(index)) * 0.3);
    const scaled = (wave + 1.0) / 2.0 * @as(f64, @floatFromInt(wave_colors.len - 1));
    const color_index: usize = @intFromFloat(@floor(scaled));
    return wave_colors[@min(color_index, wave_colors.len - 1)];
}

fn drawScanText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, frame: u64) void {
    drawScanTextWithStep(surface, col, row, text, base, frame, 3);
}

fn drawScanTextWithStep(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, frame: u64, frame_step: u64) void {
    const count = countGraphemes(text);
    const period = count + scan_colors.len + 3;
    const step = @max(frame_step, 1);
    const position: u32 = if (period == 0) 0 else @intCast((frame / step) % period);

    var cursor = col;
    var index: u32 = 0;
    var iter = chasen.text.graphemeIterator(text);
    while (iter.next()) |grapheme| : (index += 1) {
        const bytes = grapheme.bytes(text);
        var style = base;
        if (position >= index and position - index < scan_colors.len) {
            style.bold = true;
            style.fg = scan_colors[position - index];
        }
        _ = surface.borrowTextAt(cursor, row, bytes, style);
        cursor +|= chasen.text.displayWidth(bytes);
    }
}

fn countGraphemes(text: []const u8) u32 {
    var count: u32 = 0;
    var iter = chasen.text.graphemeIterator(text);
    while (iter.next()) |_| count += 1;
    return count;
}

fn drawGlitchText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, base: chasen.TextStyle, frame: u64) void {
    var cursor = col;
    var index: u32 = 0;
    var iter = chasen.text.graphemeIterator(text);
    while (iter.next()) |grapheme| : (index += 1) {
        const bytes = grapheme.bytes(text);
        var style = base;
        style.bold = true;

        const should_replace = glitchShouldReplace(frame, index, bytes);
        const rendered = if (should_replace) glitchReplacement(frame, index) else bytes;
        if (should_replace) {
            style.fg = base.fg;
        }

        _ = surface.borrowTextAt(cursor, row, rendered, style);
        cursor +|= chasen.text.displayWidth(bytes);
    }
}

fn glitchShouldReplace(frame: u64, index: u32, bytes: []const u8) bool {
    if (bytes.len == 0 or bytes[0] == ' ') return false;
    if (chasen.text.displayWidth(bytes) != 1) return false;

    // The Go version uses random replacement on a 15fps tick. Chasen runs a
    // 60fps frame loop, so quantize the frame to avoid excessive flicker while
    // keeping the same rough 8% replacement rate.
    const tick = frame / 4;
    return glitchHash(tick, index) % 100 < 8;
}

fn glitchReplacement(frame: u64, index: u32) []const u8 {
    const tick = frame / 4;
    return glitch_chars[glitchHash(tick + 17, index) % glitch_chars.len];
}

fn glitchHash(frame: u64, index: u32) usize {
    var x = frame ^ (@as(u64, index) *% 0x9e3779b97f4a7c15);
    x ^= x >> 30;
    x *%= 0xbf58476d1ce4e5b9;
    x ^= x >> 27;
    x *%= 0x94d049bb133111eb;
    x ^= x >> 31;
    return @intCast(x);
}

test "blink selection requests frames" {
    try std.testing.expect(selectionNeedsFrame("blink"));
    try std.testing.expect(!selectionNeedsFrame("none"));
    try std.testing.expect(selectionNeedsFrame("wave"));
    try std.testing.expect(selectionNeedsFrame("glitch"));
    try std.testing.expect(selectionNeedsFrame("scan"));
    try std.testing.expect(!selectionNeedsFrame("invert"));
}

test "blink focused style alternates without changing layout" {
    const base: chasen.TextStyle = .{ .bold = true, .fg = .{ .index = 14 } };
    try std.testing.expectEqual(base, focusedStyle(base, "blink", 0));
    try std.testing.expectEqual(chasen.TextStyle{}, focusedStyle(base, "blink", 45));
    try std.testing.expectEqual(base, focusedStyle(base, "none", 15));
}

test "invert focused style stays static" {
    const base: chasen.TextStyle = .{ .fg = .{ .index = 14 } };
    const style = focusedStyle(base, "invert", 0);
    try std.testing.expect(style.bold);
    try std.testing.expect(style.reverse);
    try std.testing.expect(!selectionNeedsFrame("invert"));
}

test "wave focused style remains base because color is drawn per grapheme" {
    const base: chasen.TextStyle = .{ .bold = true, .fg = .{ .index = 14 } };
    try std.testing.expectEqual(base, focusedStyle(base, "wave", 0));
    try std.testing.expectEqual(base, focusedStyle(base, "wave", 45));
}

test "wave color uses the configured palette" {
    try std.testing.expectEqual(chasen.Color{ .rgb = .{ 0x4e, 0xcd, 0xc4 } }, waveColor(0, 0));
    try std.testing.expectEqual(chasen.Color{ .rgb = .{ 0xff, 0x6b, 0x6b } }, waveColor(0, 3));
}

test "glitch skips spaces and wide graphemes" {
    try std.testing.expect(!glitchShouldReplace(0, 0, " "));
    try std.testing.expect(!glitchShouldReplace(0, 0, "あ"));
}

test "scan counts graphemes" {
    try std.testing.expectEqual(@as(u32, 3), countGraphemes("abc"));
    try std.testing.expectEqual(@as(u32, 2), countGraphemes("あb"));
}

test "glitch replacement uses configured symbol set" {
    const replacement = glitchReplacement(0, 0);
    var found = false;
    for (glitch_chars) |char| {
        if (std.mem.eql(u8, replacement, char)) found = true;
    }
    try std.testing.expect(found);
}
