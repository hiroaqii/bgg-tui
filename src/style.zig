const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

pub const Theme = struct {
    accent: chasen.Color,
    title: chasen.TextStyle,
    focused: chasen.TextStyle,
    muted: chasen.TextStyle = .{ .fg = .gray },
    subtle: chasen.TextStyle = .{ .dim = true },
    border: chasen.TextStyle,

    /// Converts the persisted interface setting into the small set of styles the
    /// app reuses across screens. Unknown names fall back to the default theme so
    /// older or manually edited config files do not break rendering.
    pub fn fromName(name: []const u8) Theme {
        if (std.mem.eql(u8, name, "mono")) return .{
            .accent = .default,
            .title = .{ .bold = true },
            .focused = .{ .bold = true, .reverse = true },
            .border = .{ .dim = true },
        };
        const accent = accentColor(name);
        return .{
            .accent = accent,
            .title = .{ .bold = true, .fg = accent },
            .focused = .{ .bold = true, .fg = accent },
            .border = .{ .fg = accent, .dim = true },
        };
    }
};

/// Maps persisted border names to the shell panel glyph set. The invisible
/// `none` preset keeps the same content geometry as the visible borders.
pub fn borderFromName(name: []const u8) ui.Panel.Border {
    if (std.mem.eql(u8, name, "none")) return .{
        .top_left = " ",
        .top = " ",
        .top_right = " ",
        .right = " ",
        .bottom_right = " ",
        .bottom = " ",
        .bottom_left = " ",
        .left = " ",
    };
    if (std.mem.eql(u8, name, "thick")) return .{
        .top_left = "┏",
        .top = "━",
        .top_right = "┓",
        .right = "┃",
        .bottom_right = "┛",
        .bottom = "━",
        .bottom_left = "┗",
        .left = "┃",
    };
    if (std.mem.eql(u8, name, "double")) return .{
        .top_left = "╔",
        .top = "═",
        .top_right = "╗",
        .right = "║",
        .bottom_right = "╝",
        .bottom = "═",
        .bottom_left = "╚",
        .left = "║",
    };
    if (std.mem.eql(u8, name, "block")) return .{
        .top_left = "█",
        .top = "▀",
        .top_right = "█",
        .right = "█",
        .bottom_right = "█",
        .bottom = "▄",
        .bottom_left = "█",
        .left = "█",
    };
    if (std.mem.eql(u8, name, "ascii")) return .{
        .top_left = "+",
        .top = "-",
        .top_right = "+",
        .right = "|",
        .bottom_right = "+",
        .bottom = "-",
        .bottom_left = "+",
        .left = "|",
    };
    return .rounded;
}

fn accentColor(name: []const u8) chasen.Color {
    if (std.mem.eql(u8, name, "blue")) return .{ .index = 12 };
    if (std.mem.eql(u8, name, "orange")) return .{ .index = 3 };
    if (std.mem.eql(u8, name, "matcha")) return .{ .rgb = .{ 118, 150, 86 } };
    return .{ .index = 14 };
}

test "theme names map to accent colors" {
    try std.testing.expectEqual(chasen.Color{ .index = 14 }, Theme.fromName("default").accent);
    try std.testing.expectEqual(chasen.Color{ .index = 12 }, Theme.fromName("blue").accent);
    try std.testing.expectEqual(chasen.Color{ .index = 3 }, Theme.fromName("orange").accent);
    try std.testing.expectEqual(chasen.Color.default, Theme.fromName("mono").accent);
    try std.testing.expectEqual(chasen.Color{ .rgb = .{ 118, 150, 86 } }, Theme.fromName("matcha").accent);
    try std.testing.expectEqual(chasen.Color{ .index = 14 }, Theme.fromName("custom").accent);
}

test "mono theme avoids accent color on primary text" {
    const theme = Theme.fromName("mono");
    try std.testing.expectEqual(chasen.Color.default, theme.title.fg);
    try std.testing.expect(theme.focused.reverse);
}

test "border names map to glyph presets" {
    try std.testing.expectEqualStrings(" ", borderFromName("none").top);
    try std.testing.expectEqualStrings("╭", borderFromName("rounded").top_left);
    try std.testing.expectEqualStrings("━", borderFromName("thick").top);
    try std.testing.expectEqualStrings("═", borderFromName("double").top);
    try std.testing.expectEqualStrings("▀", borderFromName("block").top);
    try std.testing.expectEqualStrings("-", borderFromName("ascii").top);
    try std.testing.expectEqualStrings("|", borderFromName("ascii").left);
    try std.testing.expectEqualStrings("╭", borderFromName("custom").top_left);
}
