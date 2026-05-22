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
const transition_edge_color = chasen.Color{ .rgb = .{ 0x4e, 0xcd, 0xc4 } };
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

pub fn applyScreenTransition(surface: *chasen.Surface, transition: anim.Transition) void {
    switch (transition.kind) {
        .dissolve => applyDissolveTransition(surface, transition.progress()),
        .fade => applyFadeTransition(surface, transition.progress()),
        .glitch => applyGlitchTransition(surface, transition),
        .lines => applyLinesTransition(surface, transition.progress(), false),
        .lines_cross => applyLinesTransition(surface, transition.progress(), true),
        .scanline => applyScanlineTransition(surface, transition.progress()),
        .sweep => applySweepTransition(surface, transition.progress()),
        .wipe => applyWipeTransition(surface, transition.progress()),
        else => {},
    }
}

fn applyScanlineTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const scan_position: u16 = @intFromFloat(@floor(anim.ease.clamp01(progress) * @as(f32, @floatFromInt(size.height + 1))));
    if (scan_position < size.height) {
        const style = (chasen.TextStyle{ .fg = transition_edge_color, .bold = true }).toVaxis();
        styleRow(surface, scan_position, style);
        surface.clear(.{
            .col = 0,
            .row = scan_position + 1,
            .width = size.width,
            .height = size.height - scan_position - 1,
        });
    }
}

fn styleRow(surface: *chasen.Surface, row: u16, style: anytype) void {
    const size = surface.size();
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        var cell = surface.readCell(col, row) orelse continue;
        if (cell.default) continue;
        cell.style = style;
        surface.writeCell(col, row, cell);
    }
}

fn applyDissolveTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    const clamped = anim.ease.clamp01(progress);

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (cell.default or cell.char.grapheme.len == 0 or std.mem.eql(u8, cell.char.grapheme, " ")) continue;
            if (cell.char.width != 1) continue;
            if (clamped >= dissolveThreshold(row, col)) continue;
            cell.char.grapheme = " ";
            cell.style = .{};
            surface.writeCell(col, row, cell);
        }
    }
}

fn dissolveThreshold(row: u16, col: u16) f32 {
    // Match the Go version's deterministic per-cell reveal threshold.
    const threshold = (@as(u32, row) *% 7919 + @as(u32, col) *% 6271) % 1000 + 1;
    return @as(f32, @floatFromInt(threshold)) / 1001.0;
}

fn applyFadeTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    const style = (chasen.TextStyle{ .fg = .{ .index = fadeGrayIndex(progress) } }).toVaxis();

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (cell.default) continue;
            // Match the Go version's string post-processing: ANSI styling is
            // stripped, then the whole visible frame is rendered in grayscale.
            cell.style = style;
            surface.writeCell(col, row, cell);
        }
    }
}

fn fadeGrayIndex(progress: f32) u8 {
    const clamped = anim.ease.clamp01(progress);
    const gray: u8 = @intFromFloat(@floor(232.0 + clamped * 23.0));
    return @min(gray, 255);
}

fn applyGlitchTransition(surface: *chasen.Surface, transition: anim.Transition) void {
    const size = surface.size();
    const threshold = transitionGlitchThreshold(transition.progress());
    const tick = transition.frame / 5;
    const style = (chasen.TextStyle{ .fg = transition_edge_color }).toVaxis();

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (cell.default or cell.char.grapheme.len == 0 or std.mem.eql(u8, cell.char.grapheme, " ")) continue;
            if (cell.char.width != 1) continue;
            if (transitionGlitchHash(tick, row, col) % 1000 >= threshold) continue;

            cell.char.grapheme = transitionGlitchReplacement(tick, row, col);
            cell.style = style;
            surface.writeCell(col, row, cell);
        }
    }
}

fn transitionGlitchThreshold(progress: f32) u16 {
    const clamped = anim.ease.clamp01(progress);
    const remaining = 1.0 - clamped;
    // Go version uses 0.4 * (1 - progress). Use a denser start and steeper
    // decay so the effect is more visible at entry but does not linger.
    const squared = remaining * remaining;
    const fourth = squared * squared;
    const decay = fourth * fourth;
    return @intFromFloat(@floor(400.0 * decay));
}

fn transitionGlitchReplacement(frame: u64, row: u16, col: u16) []const u8 {
    return glitch_chars[transitionGlitchHash(frame + 17, row, col) % glitch_chars.len];
}

fn transitionGlitchHash(frame: u64, row: u16, col: u16) usize {
    const index = @as(u32, row) *% 4099 + @as(u32, col);
    return glitchHash(frame, index);
}

fn applyLinesTransition(surface: *chasen.Surface, progress: f32, cross: bool) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const clamped = anim.ease.clamp01(progress);
    const total_rows = @as(f32, @floatFromInt(size.height));

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        const line_width = lineContentWidth(surface, row);
        if (line_width == 0) continue;

        const line_delay = @as(f32, @floatFromInt(row)) / total_rows * 0.6;
        const raw_line_progress = (clamped - line_delay) / 0.4;
        const line_progress = easeOutQuad(raw_line_progress);
        if (line_progress >= 1.0) continue;

        if (cross and row % 2 == 1) {
            revealLineFromLeft(surface, row, line_width, line_progress);
        } else {
            revealLineFromRight(surface, row, line_width, line_progress);
        }
    }
}

fn lineContentWidth(surface: *chasen.Surface, row: u16) u16 {
    const size = surface.size();
    var width: u16 = 0;
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        const cell = surface.readCell(col, row) orelse continue;
        if (cell.default or cell.char.grapheme.len == 0 or std.mem.eql(u8, cell.char.grapheme, " ")) continue;
        width = @max(width, col +| cell.char.width);
    }
    return width;
}

fn revealLineFromRight(surface: *chasen.Surface, row: u16, line_width: u16, progress: f32) void {
    const offset: u16 = @intFromFloat(@floor(@as(f32, @floatFromInt(line_width)) * (1.0 - progress)));
    const visible_cols = line_width -| offset;

    var remaining = visible_cols;
    while (remaining > 0) {
        remaining -= 1;
        const source_col = remaining;
        const target_col = source_col +| offset;
        if (surface.readCell(source_col, row)) |cell| {
            if (cell.char.width == 1) {
                surface.writeCell(target_col, row, cell);
                continue;
            }
        }
        clearCell(surface, target_col, row);
    }
    clearRowRange(surface, row, 0, offset);
}

fn revealLineFromLeft(surface: *chasen.Surface, row: u16, line_width: u16, progress: f32) void {
    const visible_cols: u16 = @intFromFloat(@floor(@as(f32, @floatFromInt(line_width)) * progress));
    const source_start = line_width -| visible_cols;

    var source_col = source_start;
    while (source_col < line_width) : (source_col += 1) {
        const target_col = source_col -| source_start;
        if (surface.readCell(source_col, row)) |cell| {
            if (cell.char.width == 1) {
                surface.writeCell(target_col, row, cell);
                continue;
            }
        }
        clearCell(surface, target_col, row);
    }
    clearRowRange(surface, row, visible_cols, line_width -| visible_cols);
}

fn clearCell(surface: *chasen.Surface, col: u16, row: u16) void {
    surface.clear(.{ .col = col, .row = row, .width = 1, .height = 1 });
}

fn clearRowRange(surface: *chasen.Surface, row: u16, col: u16, width: u16) void {
    if (width == 0) return;
    surface.clear(.{ .col = col, .row = row, .width = width, .height = 1 });
}

fn applyWipeTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const visible_width: u16 = @intFromFloat(@floor(anim.ease.clamp01(progress) * @as(f32, @floatFromInt(size.width))));
    if (visible_width >= size.width) return;

    surface.clear(.{
        .col = visible_width,
        .row = 0,
        .width = size.width - visible_width,
        .height = size.height,
    });
}

fn applySweepTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const eased = easeOutQuad(progress);
    const sweep_col: u16 = @intFromFloat(@floor(eased * @as(f32, @floatFromInt(size.width))));

    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        if (col < sweep_col) continue;
        if (col == sweep_col and sweep_col > 0) {
            drawSweepEdge(surface, col);
            continue;
        }
        surface.clear(.{
            .col = col,
            .row = 0,
            .width = 1,
            .height = size.height,
        });
    }
}

fn drawSweepEdge(surface: *chasen.Surface, col: u16) void {
    const size = surface.size();
    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        _ = surface.borrowTextAt(col, row, "▌", .{ .fg = transition_edge_color });
    }
}

fn easeOutQuad(progress: f32) f32 {
    const clamped = anim.ease.clamp01(progress);
    return 1.0 - (1.0 - clamped) * (1.0 - clamped);
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

test "sweep screen transition clears unrevealed columns and draws edge" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 2);
    defer ts.deinit();
    ts.surface.fillAll(.{ .char = .{ .grapheme = "x", .width = 1 } });

    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .sweep,
        .frame = 2,
        .max_frame = 4,
    });

    try std.testing.expectEqualStrings("x", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("x", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("x", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("▌", ts.surface.readCell(3, 0).?.char.grapheme);
}

test "sweep easing matches go version shape" {
    try std.testing.expectEqual(@as(f32, 0.0), easeOutQuad(0.0));
    try std.testing.expectEqual(@as(f32, 0.75), easeOutQuad(0.5));
    try std.testing.expectEqual(@as(f32, 1.0), easeOutQuad(1.0));
}

test "fade screen transition maps progress to go grayscale range" {
    try std.testing.expectEqual(@as(u8, 232), fadeGrayIndex(0.0));
    try std.testing.expectEqual(@as(u8, 243), fadeGrayIndex(0.5));
    try std.testing.expectEqual(@as(u8, 255), fadeGrayIndex(1.0));
}

test "fade screen transition replaces visible cell style with grayscale" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(2, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "A", .{ .bold = true, .fg = .{ .index = 2 } });
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .fade,
        .frame = 0,
        .max_frame = 10,
    });

    const cell = ts.surface.readCell(0, 0).?;
    try std.testing.expectEqualStrings("A", cell.char.grapheme);
    try std.testing.expect(cell.style.fg.eql(.{ .index = 232 }));
    try std.testing.expect(!cell.style.bold);
}

test "glitch screen transition probability decreases with progress" {
    try std.testing.expectEqual(@as(u16, 400), transitionGlitchThreshold(0.0));
    try std.testing.expectEqual(@as(u16, 1), transitionGlitchThreshold(0.5));
    try std.testing.expectEqual(@as(u16, 0), transitionGlitchThreshold(1.0));
}

test "glitch screen transition replaces matching visible cells" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(8, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCDEFGH", .{ .bold = true });
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .glitch,
        .frame = 0,
        .max_frame = 10,
    });

    var replaced = false;
    var col: u16 = 0;
    while (col < 8) : (col += 1) {
        const expected = "ABCDEFGH"[col .. col + 1];
        const actual = ts.surface.readCell(col, 0).?.char.grapheme;
        if (!std.mem.eql(u8, expected, actual)) replaced = true;
    }
    try std.testing.expect(replaced);
}

test "dissolve threshold follows go version formula" {
    try std.testing.expectEqual(@as(f32, 1.0 / 1001.0), dissolveThreshold(0, 0));
    try std.testing.expectEqual(@as(f32, 920.0 / 1001.0), dissolveThreshold(1, 0));
    try std.testing.expectEqual(@as(f32, 272.0 / 1001.0), dissolveThreshold(0, 1));
}

test "dissolve screen transition clears cells above threshold" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(2, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "AB", .{ .bold = true });
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .dissolve,
        .frame = 100,
        .max_frame = 1000,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(1, 0).?.char.grapheme);
}

test "lines screen transition staggers rows from the right" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 2);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "AB", .{});
    _ = ts.surface.borrowTextAt(0, 1, "CD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .lines,
        .frame = 10,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("A", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 1).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(1, 1).?.char.grapheme);
}

test "lines-cross screen transition alternates row direction" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 2);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "AB", .{});
    _ = ts.surface.borrowTextAt(0, 1, "CD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .lines_cross,
        .frame = 50,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("D", ts.surface.readCell(0, 1).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(1, 1).?.char.grapheme);
}

test "wipe screen transition clears unrevealed right side" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .wipe,
        .frame = 50,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(3, 0).?.char.grapheme);
}

test "scanline screen transition highlights current row and clears following rows" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(2, 3);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "AB", .{});
    _ = ts.surface.borrowTextAt(0, 1, "CD", .{});
    _ = ts.surface.borrowTextAt(0, 2, "EF", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .scanline,
        .frame = 10,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expect(ts.surface.readCell(0, 0).?.style.fg.eql(.{ .rgb = .{ 0x4e, 0xcd, 0xc4 } }));
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 1).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 2).?.char.grapheme);
}
