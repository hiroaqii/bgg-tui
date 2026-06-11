const std = @import("std");
const chasen = @import("chasen");

pub const transition_edge_color = chasen.Color{ .rgb = .{ 0x4e, 0xcd, 0xc4 } };
pub const glitch_chars = [_][]const u8{ "@", "#", "$", "%", "&", "*", "!", "?", "+", "=", "~", "^", "x", "X", "░", "▒", "▓", "█" };

pub fn isVisibleSingleWidthCell(cell: anytype) bool {
    return cell.isVisibleText() and cell.char.width == 1;
}

pub fn clearCell(surface: *chasen.Surface, col: u16, row: u16) void {
    surface.clear(.{ .col = col, .row = row, .width = 1, .height = 1 });
}

pub fn clearRowRange(surface: *chasen.Surface, row: u16, col: u16, width: u16) void {
    if (width == 0) return;
    surface.clear(.{ .col = col, .row = row, .width = width, .height = 1 });
}

pub fn copyCellOrClear(surface: *chasen.Surface, source_col: u16, target_col: u16, row: u16) void {
    if (surface.readCell(source_col, row)) |cell| {
        if (!cell.isBlank() and cell.char.width == 1) {
            surface.writeCell(target_col, row, cell);
            return;
        }
    }
    clearCell(surface, target_col, row);
}

pub fn glitchHash(frame: u64, index: u32) usize {
    var x = frame ^ (@as(u64, index) *% 0x9e3779b97f4a7c15);
    x ^= x >> 30;
    x *%= 0xbf58476d1ce4e5b9;
    x ^= x >> 27;
    x *%= 0x94d049bb133111eb;
    x ^= x >> 31;
    return @intCast(x);
}
