const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");

const blink_period: u64 = 90;

pub fn selectionNeedsFrame(selection: []const u8) bool {
    return std.mem.eql(u8, selection, "blink");
}

pub fn focusedStyle(base: chasen.TextStyle, selection: []const u8, frame: u64) chasen.TextStyle {
    if (!std.mem.eql(u8, selection, "blink")) return base;
    return if (anim.blink.isOn(frame, blink_period, 0.5)) base else .{};
}

test "blink selection requests frames" {
    try std.testing.expect(selectionNeedsFrame("blink"));
    try std.testing.expect(!selectionNeedsFrame("none"));
    try std.testing.expect(!selectionNeedsFrame("wave"));
}

test "blink focused style alternates without changing layout" {
    const base: chasen.TextStyle = .{ .bold = true, .fg = .{ .index = 14 } };
    try std.testing.expectEqual(base, focusedStyle(base, "blink", 0));
    try std.testing.expectEqual(chasen.TextStyle{}, focusedStyle(base, "blink", 45));
    try std.testing.expectEqual(base, focusedStyle(base, "none", 15));
}
