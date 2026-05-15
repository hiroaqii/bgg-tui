const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn decodeEntities(allocator: Allocator, input: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var index: usize = 0;
    while (index < input.len) {
        if (input[index] != '&') {
            try out.writer.writeByte(input[index]);
            index += 1;
            continue;
        }

        const semicolon = std.mem.indexOfScalarPos(u8, input, index, ';') orelse {
            try out.writer.writeByte(input[index]);
            index += 1;
            continue;
        };

        const entity = input[index + 1 .. semicolon];
        if (try writeEntity(&out.writer, entity)) {
            index = semicolon + 1;
        } else {
            try out.writer.writeAll(input[index .. semicolon + 1]);
            index = semicolon + 1;
        }
    }

    return try out.toOwnedSlice();
}

fn writeEntity(writer: *std.Io.Writer, entity: []const u8) !bool {
    if (namedEntityValue(entity)) |value| {
        try writer.writeAll(value);
    } else if (std.mem.startsWith(u8, entity, "#x") or std.mem.startsWith(u8, entity, "#X")) {
        try writeCodepoint(writer, std.fmt.parseInt(u21, entity[2..], 16) catch return false);
    } else if (std.mem.startsWith(u8, entity, "#")) {
        try writeCodepoint(writer, std.fmt.parseInt(u21, entity[1..], 10) catch return false);
    } else {
        return false;
    }

    return true;
}

fn namedEntityValue(entity: []const u8) ?[]const u8 {
    const Entity = struct {
        name: []const u8,
        value: []const u8,
    };

    const entities = [_]Entity{
        .{ .name = "amp", .value = "&" },
        .{ .name = "apos", .value = "'" },
        .{ .name = "quot", .value = "\"" },
        .{ .name = "lt", .value = "<" },
        .{ .name = "gt", .value = ">" },
        .{ .name = "nbsp", .value = " " },
        .{ .name = "iexcl", .value = "¡" },
        .{ .name = "cent", .value = "¢" },
        .{ .name = "pound", .value = "£" },
        .{ .name = "curren", .value = "¤" },
        .{ .name = "yen", .value = "¥" },
        .{ .name = "brvbar", .value = "¦" },
        .{ .name = "sect", .value = "§" },
        .{ .name = "uml", .value = "¨" },
        .{ .name = "copy", .value = "©" },
        .{ .name = "ordf", .value = "ª" },
        .{ .name = "laquo", .value = "«" },
        .{ .name = "not", .value = "¬" },
        .{ .name = "shy", .value = "\u{00ad}" },
        .{ .name = "reg", .value = "®" },
        .{ .name = "macr", .value = "¯" },
        .{ .name = "deg", .value = "°" },
        .{ .name = "plusmn", .value = "±" },
        .{ .name = "sup2", .value = "²" },
        .{ .name = "sup3", .value = "³" },
        .{ .name = "acute", .value = "´" },
        .{ .name = "micro", .value = "µ" },
        .{ .name = "para", .value = "¶" },
        .{ .name = "middot", .value = "·" },
        .{ .name = "cedil", .value = "¸" },
        .{ .name = "sup1", .value = "¹" },
        .{ .name = "ordm", .value = "º" },
        .{ .name = "raquo", .value = "»" },
        .{ .name = "frac14", .value = "¼" },
        .{ .name = "frac12", .value = "½" },
        .{ .name = "frac34", .value = "¾" },
        .{ .name = "iquest", .value = "¿" },
        .{ .name = "Agrave", .value = "À" },
        .{ .name = "Aacute", .value = "Á" },
        .{ .name = "Acirc", .value = "Â" },
        .{ .name = "Atilde", .value = "Ã" },
        .{ .name = "Auml", .value = "Ä" },
        .{ .name = "Aring", .value = "Å" },
        .{ .name = "AElig", .value = "Æ" },
        .{ .name = "Ccedil", .value = "Ç" },
        .{ .name = "Egrave", .value = "È" },
        .{ .name = "Eacute", .value = "É" },
        .{ .name = "Ecirc", .value = "Ê" },
        .{ .name = "Euml", .value = "Ë" },
        .{ .name = "Igrave", .value = "Ì" },
        .{ .name = "Iacute", .value = "Í" },
        .{ .name = "Icirc", .value = "Î" },
        .{ .name = "Iuml", .value = "Ï" },
        .{ .name = "ETH", .value = "Ð" },
        .{ .name = "Ntilde", .value = "Ñ" },
        .{ .name = "Ograve", .value = "Ò" },
        .{ .name = "Oacute", .value = "Ó" },
        .{ .name = "Ocirc", .value = "Ô" },
        .{ .name = "Otilde", .value = "Õ" },
        .{ .name = "Ouml", .value = "Ö" },
        .{ .name = "times", .value = "×" },
        .{ .name = "Oslash", .value = "Ø" },
        .{ .name = "Ugrave", .value = "Ù" },
        .{ .name = "Uacute", .value = "Ú" },
        .{ .name = "Ucirc", .value = "Û" },
        .{ .name = "Uuml", .value = "Ü" },
        .{ .name = "Yacute", .value = "Ý" },
        .{ .name = "THORN", .value = "Þ" },
        .{ .name = "szlig", .value = "ß" },
        .{ .name = "agrave", .value = "à" },
        .{ .name = "aacute", .value = "á" },
        .{ .name = "acirc", .value = "â" },
        .{ .name = "atilde", .value = "ã" },
        .{ .name = "auml", .value = "ä" },
        .{ .name = "aring", .value = "å" },
        .{ .name = "aelig", .value = "æ" },
        .{ .name = "ccedil", .value = "ç" },
        .{ .name = "egrave", .value = "è" },
        .{ .name = "eacute", .value = "é" },
        .{ .name = "ecirc", .value = "ê" },
        .{ .name = "euml", .value = "ë" },
        .{ .name = "igrave", .value = "ì" },
        .{ .name = "iacute", .value = "í" },
        .{ .name = "icirc", .value = "î" },
        .{ .name = "iuml", .value = "ï" },
        .{ .name = "eth", .value = "ð" },
        .{ .name = "ntilde", .value = "ñ" },
        .{ .name = "ograve", .value = "ò" },
        .{ .name = "oacute", .value = "ó" },
        .{ .name = "ocirc", .value = "ô" },
        .{ .name = "otilde", .value = "õ" },
        .{ .name = "ouml", .value = "ö" },
        .{ .name = "divide", .value = "÷" },
        .{ .name = "oslash", .value = "ø" },
        .{ .name = "ugrave", .value = "ù" },
        .{ .name = "uacute", .value = "ú" },
        .{ .name = "ucirc", .value = "û" },
        .{ .name = "uuml", .value = "ü" },
        .{ .name = "yacute", .value = "ý" },
        .{ .name = "thorn", .value = "þ" },
        .{ .name = "yuml", .value = "ÿ" },
        .{ .name = "ndash", .value = "–" },
        .{ .name = "mdash", .value = "—" },
        .{ .name = "lsquo", .value = "‘" },
        .{ .name = "rsquo", .value = "’" },
        .{ .name = "sbquo", .value = "‚" },
        .{ .name = "ldquo", .value = "“" },
        .{ .name = "rdquo", .value = "”" },
        .{ .name = "bdquo", .value = "„" },
        .{ .name = "dagger", .value = "†" },
        .{ .name = "Dagger", .value = "‡" },
        .{ .name = "bull", .value = "•" },
        .{ .name = "hellip", .value = "…" },
        .{ .name = "permil", .value = "‰" },
        .{ .name = "prime", .value = "′" },
        .{ .name = "Prime", .value = "″" },
        .{ .name = "lsaquo", .value = "‹" },
        .{ .name = "rsaquo", .value = "›" },
        .{ .name = "oline", .value = "‾" },
        .{ .name = "frasl", .value = "⁄" },
        .{ .name = "euro", .value = "€" },
        .{ .name = "trade", .value = "™" },
    };

    for (entities) |item| {
        if (std.mem.eql(u8, entity, item.name)) return item.value;
    }

    return null;
}

fn writeCodepoint(writer: *std.Io.Writer, codepoint: u21) !void {
    if (codepoint == '\r') return;
    if (codepoint == '\n') {
        try writer.writeByte('\n');
        return;
    }

    var buffer: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(codepoint, &buffer) catch return;
    try writer.writeAll(buffer[0..len]);
}

test "decode named HTML entities" {
    const decoded = try decodeEntities(std.testing.allocator, "&amp; &apos; &quot; &lt;tag&gt; &nbsp;");
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings("& ' \" <tag>  ", decoded);
}

test "decode common BGG text entities" {
    const decoded = try decodeEntities(
        std.testing.allocator,
        "It&rsquo;s &ldquo;fast&rdquo;&mdash;but caf&eacute; rules aren&rsquo;t official&hellip;",
    );
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings("It’s “fast”—but café rules aren’t official…", decoded);
}

test "decode decimal and hexadecimal numeric entities" {
    const decoded = try decodeEntities(std.testing.allocator, "Line1&#10;Line2 &#x263A;");
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings("Line1\nLine2 ☺", decoded);
}

test "decode BGG double-escaped newline after XML entity expansion" {
    const decoded = try decodeEntities(std.testing.allocator, "Line1&#10;&#10;Line2");
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings("Line1\n\nLine2", decoded);
}

test "preserve unknown entities" {
    const decoded = try decodeEntities(std.testing.allocator, "A &unknown; entity");
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualStrings("A &unknown; entity", decoded);
}
