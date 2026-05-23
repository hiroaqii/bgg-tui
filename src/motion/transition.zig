const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");
const common = @import("common.zig");

const code_rain_chars = [_][]const u8{ "0", "1", "3", "7", "9", "A", "B", "C", "D", "E", "F", "$", "#", "@", "%", "&", "+", "=", "░", "▒", "▓" };

pub fn applyScreenTransition(surface: *chasen.Surface, transition: anim.Transition) void {
    switch (transition.kind) {
        .code_rain => applyCodeRainTransition(surface, transition),
        .dissolve => applyDissolveTransition(surface, transition.progress()),
        .fade => applyFadeTransition(surface, transition.progress()),
        .glitch => applyGlitchTransition(surface, transition),
        .iris => applyIrisTransition(surface, transition.progress()),
        .lines => applyLinesTransition(surface, transition.progress(), false),
        .lines_cross => applyLinesTransition(surface, transition.progress(), true),
        .scanline => applyScanlineTransition(surface, transition.progress()),
        .shutter => applyShutterTransition(surface, transition.progress()),
        .spiral => applySpiralTransition(surface, transition.progress()),
        .sweep => applySweepTransition(surface, transition.progress()),
        .warp => applyWarpTransition(surface, transition.progress()),
        else => {},
    }
}

fn applyScanlineTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const scan_position: u16 = @intFromFloat(@floor(anim.ease.clamp01(progress) * @as(f32, @floatFromInt(size.height + 1))));
    if (scan_position < size.height) {
        const style = (chasen.TextStyle{ .fg = common.transition_edge_color, .bold = true }).toVaxis();
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
            if (!common.isVisibleSingleWidthCell(cell)) continue;
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
    const style = (chasen.TextStyle{ .fg = common.transition_edge_color }).toVaxis();

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (!common.isVisibleSingleWidthCell(cell)) continue;
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
    return common.glitch_chars[transitionGlitchHash(frame + 17, row, col) % common.glitch_chars.len];
}

fn transitionGlitchHash(frame: u64, row: u16, col: u16) usize {
    const index = @as(u32, row) *% 4099 + @as(u32, col);
    return common.glitchHash(frame, index);
}

fn applyCodeRainTransition(surface: *chasen.Surface, transition: anim.Transition) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const progress = anim.ease.clamp01(transition.progress());
    if (progress >= 1.0) return;

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (!common.isVisibleSingleWidthCell(cell)) continue;
            if (progress >= codeRainRevealThreshold(row, col, size.height)) continue;

            if (!codeRainShouldRender(progress, transition.frame, row, col, size.height)) {
                common.clearCell(surface, col, row);
                continue;
            }

            cell.char.grapheme = codeRainReplacement(transition.frame, row, col);
            cell.style = codeRainStyle(progress, transition.frame, row, col, size.height).toVaxis();
            surface.writeCell(col, row, cell);
        }
    }
}

fn codeRainRevealThreshold(row: u16, col: u16, height: u16) f32 {
    const height_f = @max(@as(f32, @floatFromInt(height)), 1.0);
    const row_delay = @as(f32, @floatFromInt(row)) / height_f * 0.48;
    const jitter_hash = transitionGlitchHash(23, row, col) % 100;
    const jitter = @as(f32, @floatFromInt(jitter_hash)) / 100.0 * 0.28;
    return @min(0.96, 0.22 + row_delay + jitter);
}

fn codeRainShouldRender(progress: f32, frame: u64, row: u16, col: u16, height: u16) bool {
    const head = codeRainHead(progress, frame, col, height);
    const row_f = @as(f32, @floatFromInt(row));
    const trail = 6.0;
    return row_f <= head and row_f >= head - trail;
}

fn codeRainStyle(progress: f32, frame: u64, row: u16, col: u16, height: u16) chasen.TextStyle {
    const head = codeRainHead(progress, frame, col, height);
    const row_f = @as(f32, @floatFromInt(row));
    if (head - row_f <= 1.0) {
        return .{ .fg = .{ .rgb = .{ 0xd8, 0xff, 0xd8 } }, .bold = true };
    }
    return .{ .fg = .{ .rgb = .{ 0x00, 0xd7, 0x5f } } };
}

fn codeRainHead(progress: f32, frame: u64, col: u16, height: u16) f32 {
    const height_f = @as(f32, @floatFromInt(height));
    const column_offset = @as(f32, @floatFromInt(transitionGlitchHash(frame / 8, 0, col) % 7));
    return progress * (height_f + 10.0) - 5.0 + column_offset;
}

fn codeRainReplacement(frame: u64, row: u16, col: u16) []const u8 {
    return code_rain_chars[transitionGlitchHash(frame / 5 + 41, row, col) % code_rain_chars.len];
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
        common.clearCell(surface, target_col, row);
    }
    common.clearRowRange(surface, row, 0, offset);
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
        common.clearCell(surface, target_col, row);
    }
    common.clearRowRange(surface, row, visible_cols, line_width -| visible_cols);
}

fn applySpiralTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const clamped = anim.ease.clamp01(progress);
    if (clamped >= 1.0) return;
    const edge_style = (chasen.TextStyle{ .fg = common.transition_edge_color, .bold = true }).toVaxis();

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            var cell = surface.readCell(col, row) orelse continue;
            if (!common.isVisibleSingleWidthCell(cell)) continue;

            const threshold = spiralThreshold(row, col, size);
            if (clamped < threshold) {
                common.clearCell(surface, col, row);
                continue;
            }
            if (clamped - threshold < 0.035) {
                cell.style = edge_style;
                surface.writeCell(col, row, cell);
            }
        }
    }
}

fn spiralThreshold(row: u16, col: u16, size: chasen.Size) f32 {
    const half_width = @max(@as(f64, @floatFromInt(size.width -| 1)) / 2.0, 1.0);
    const half_height = @max(@as(f64, @floatFromInt(size.height -| 1)) / 2.0, 1.0);
    const center_col = @as(f64, @floatFromInt(size.width -| 1)) / 2.0;
    const center_row = @as(f64, @floatFromInt(size.height -| 1)) / 2.0;
    const dx = (@as(f64, @floatFromInt(col)) - center_col) / half_width;
    const dy = (@as(f64, @floatFromInt(row)) - center_row) / half_height;
    const radius = @min(@sqrt(dx * dx + dy * dy) / @sqrt(2.0), 1.0);
    const angle = std.math.atan2(dy, dx);
    const angle_norm = (angle + std.math.pi) / (std.math.pi * 2.0);
    const twist = fract(angle_norm + radius * 1.35);
    return @floatCast(@min(0.98, 0.06 + radius * 0.68 + twist * 0.26));
}

fn fract(value: f64) f64 {
    return value - @floor(value);
}

fn applyWarpTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const clamped = anim.ease.clamp01(progress);
    if (clamped >= 1.0) return;

    const remaining = 1.0 - smoothStep(clamped);
    const amplitude = @as(i16, @intFromFloat(@floor(6.0 * remaining)));
    if (amplitude == 0) return;

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        const row_phase = @as(f64, @floatFromInt(row)) * 0.72 + @as(f64, @floatCast(clamped)) * 8.0;
        const offset: i16 = @intFromFloat(@round(std.math.sin(row_phase) * @as(f64, @floatFromInt(amplitude))));
        shiftRow(surface, row, offset);
    }
}

fn shiftRow(surface: *chasen.Surface, row: u16, offset: i16) void {
    const size = surface.size();
    if (offset == 0 or size.width == 0) return;

    const magnitude: u16 = @intCast(@abs(offset));
    if (magnitude >= size.width) {
        common.clearRowRange(surface, row, 0, size.width);
        return;
    }

    if (offset > 0) {
        var remaining = size.width;
        while (remaining > 0) {
            remaining -= 1;
            const target_col = remaining;
            if (target_col < magnitude) {
                common.clearCell(surface, target_col, row);
                continue;
            }
            common.copyCellOrClear(surface, target_col - magnitude, target_col, row);
        }
    } else {
        var target_col: u16 = 0;
        while (target_col < size.width) : (target_col += 1) {
            const source_col = target_col + magnitude;
            if (source_col >= size.width) {
                common.clearCell(surface, target_col, row);
                continue;
            }
            common.copyCellOrClear(surface, source_col, target_col, row);
        }
    }
}

fn applyIrisTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const clamped = anim.ease.clamp01(progress);
    const half_width = @max(@as(f32, @floatFromInt(size.width -| 1)) / 2.0, 1.0);
    const half_height = @max(@as(f32, @floatFromInt(size.height -| 1)) / 2.0, 1.0);
    const center_col = @as(f32, @floatFromInt(size.width -| 1)) / 2.0;
    const center_row = @as(f32, @floatFromInt(size.height -| 1)) / 2.0;
    const max_distance = @sqrt(1.0 * 1.0 + 1.0 * 1.0);

    var row: u16 = 0;
    while (row < size.height) : (row += 1) {
        var col: u16 = 0;
        while (col < size.width) : (col += 1) {
            const dx = (@as(f32, @floatFromInt(col)) - center_col) / half_width;
            const dy = (@as(f32, @floatFromInt(row)) - center_row) / half_height;
            const distance = @sqrt(dx * dx + dy * dy) / max_distance;
            if (distance <= clamped) continue;
            common.clearCell(surface, col, row);
        }
    }
}

fn applyShutterTransition(surface: *chasen.Surface, progress: f32) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    const visible_height: u16 = @intFromFloat(@ceil(smoothStep(progress) * @as(f32, @floatFromInt(size.height))));
    if (visible_height >= size.height) return;

    const start_row = (size.height - visible_height) / 2;
    const end_row = start_row + visible_height;
    if (start_row > 0) {
        surface.clear(.{
            .col = 0,
            .row = 0,
            .width = size.width,
            .height = start_row,
        });
    }
    if (end_row < size.height) {
        surface.clear(.{
            .col = 0,
            .row = end_row,
            .width = size.width,
            .height = size.height - end_row,
        });
    }
    drawShutterEdge(surface, start_row, end_row);
}

fn drawShutterEdge(surface: *chasen.Surface, start_row: u16, end_row: u16) void {
    const size = surface.size();
    if (size.width == 0 or size.height == 0) return;

    if (start_row > 0) drawHorizontalEdge(surface, start_row - 1);
    if (end_row < size.height) drawHorizontalEdge(surface, end_row);
}

fn drawHorizontalEdge(surface: *chasen.Surface, row: u16) void {
    const size = surface.size();
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        _ = surface.borrowTextAt(col, row, "─", .{ .fg = common.transition_edge_color });
    }
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
        _ = surface.borrowTextAt(col, row, "▌", .{ .fg = common.transition_edge_color });
    }
}

fn easeOutQuad(progress: f32) f32 {
    const clamped = anim.ease.clamp01(progress);
    return 1.0 - (1.0 - clamped) * (1.0 - clamped);
}

fn smoothStep(progress: f32) f32 {
    const clamped = anim.ease.clamp01(progress);
    return clamped * clamped * (3.0 - 2.0 * clamped);
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

test "code-rain screen transition replaces unrevealed visible cells" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(8, 2);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCDEFGH", .{});
    _ = ts.surface.borrowTextAt(0, 1, "IJKLMNOP", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .code_rain,
        .frame = 20,
        .max_frame = 110,
    });

    var changed = false;
    var row: u16 = 0;
    while (row < 2) : (row += 1) {
        var col: u16 = 0;
        while (col < 8) : (col += 1) {
            const expected = if (row == 0) "ABCDEFGH"[col .. col + 1] else "IJKLMNOP"[col .. col + 1];
            const actual = ts.surface.readCell(col, row).?.char.grapheme;
            if (!std.mem.eql(u8, expected, actual)) changed = true;
        }
    }
    try std.testing.expect(changed);
}

test "code-rain screen transition preserves completed content" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .code_rain,
        .frame = 110,
        .max_frame = 110,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("C", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("D", ts.surface.readCell(3, 0).?.char.grapheme);
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

test "spiral screen transition reveals center before corner" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(5, 5);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "A", .{});
    _ = ts.surface.borrowTextAt(2, 2, "X", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .spiral,
        .frame = 25,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("X", ts.surface.readCell(2, 2).?.char.grapheme);
}

test "spiral screen transition preserves completed content" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .spiral,
        .frame = 104,
        .max_frame = 104,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("C", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("D", ts.surface.readCell(3, 0).?.char.grapheme);
}

test "warp screen transition shifts rows while settling" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(6, 2);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCDEF", .{});
    _ = ts.surface.borrowTextAt(0, 1, "GHIJKL", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .warp,
        .frame = 12,
        .max_frame = 96,
    });

    var changed = false;
    var row: u16 = 0;
    while (row < 2) : (row += 1) {
        var col: u16 = 0;
        while (col < 6) : (col += 1) {
            const expected = if (row == 0) "ABCDEF"[col .. col + 1] else "GHIJKL"[col .. col + 1];
            const actual = ts.surface.readCell(col, row).?.char.grapheme;
            if (!std.mem.eql(u8, expected, actual)) changed = true;
        }
    }
    try std.testing.expect(changed);
}

test "warp screen transition preserves completed content" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .warp,
        .frame = 96,
        .max_frame = 96,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("C", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("D", ts.surface.readCell(3, 0).?.char.grapheme);
}

test "warp screen transition settles before the final frame" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(4, 1);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "ABCD", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .warp,
        .frame = 95,
        .max_frame = 96,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("B", ts.surface.readCell(1, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("C", ts.surface.readCell(2, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("D", ts.surface.readCell(3, 0).?.char.grapheme);
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

test "iris screen transition reveals from center outward" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(5, 5);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "A", .{});
    _ = ts.surface.borrowTextAt(2, 2, "X", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .iris,
        .frame = 10,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("X", ts.surface.readCell(2, 2).?.char.grapheme);
}

test "iris screen transition reveals corners at completion" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(5, 5);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "A", .{});
    _ = ts.surface.borrowTextAt(4, 4, "Z", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .iris,
        .frame = 100,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings("A", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("Z", ts.surface.readCell(4, 4).?.char.grapheme);
}

test "shutter screen transition reveals a centered horizontal band" {
    var ts: chasen.testing.TestSurface = undefined;
    try ts.init(1, 5);
    defer ts.deinit();

    _ = ts.surface.borrowTextAt(0, 0, "A", .{});
    _ = ts.surface.borrowTextAt(0, 2, "C", .{});
    _ = ts.surface.borrowTextAt(0, 4, "E", .{});
    applyScreenTransition(&ts.surface, anim.Transition{
        .kind = .shutter,
        .frame = 40,
        .max_frame = 100,
    });

    try std.testing.expectEqualStrings("─", ts.surface.readCell(0, 0).?.char.grapheme);
    try std.testing.expectEqualStrings("C", ts.surface.readCell(0, 2).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", ts.surface.readCell(0, 4).?.char.grapheme);
}
