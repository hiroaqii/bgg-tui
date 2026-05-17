const std = @import("std");

const Allocator = std.mem.Allocator;

pub const TextOptions = struct {
    quote_prefix: []const u8 = "> ",
    wrap_width: ?usize = null,
    linkify_urls: bool = false,
};

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

pub fn toText(allocator: Allocator, input: []const u8, options: TextOptions) ![]u8 {
    var renderer = TextRenderer.init(allocator, options);
    defer renderer.deinit();

    try renderer.render(input);
    var text = try renderer.toOwnedSlice();
    errdefer allocator.free(text);

    if (options.wrap_width) |width| {
        const wrapped = try wrapText(allocator, text, width, options.quote_prefix);
        allocator.free(text);
        text = wrapped;
    }

    if (options.linkify_urls) {
        const linkified = try linkifyUrls(allocator, text);
        allocator.free(text);
        text = linkified;
    }

    return text;
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

const TextRenderer = struct {
    out: std.Io.Writer.Allocating,
    options: TextOptions,
    at_line_start: bool = true,
    pending_space: bool = false,
    newline_count: usize = 0,
    quote_depth: usize = 0,
    div_depth: usize = 0,
    quote_div_depths: [16]usize = undefined,
    quote_div_depth_count: usize = 0,
    active_link: ?LinkInfo = null,

    fn init(allocator: Allocator, options: TextOptions) TextRenderer {
        return .{
            .out = .init(allocator),
            .options = options,
        };
    }

    fn deinit(self: *TextRenderer) void {
        self.out.deinit();
    }

    fn toOwnedSlice(self: *TextRenderer) ![]u8 {
        return try self.out.toOwnedSlice();
    }

    fn render(self: *TextRenderer, input: []const u8) !void {
        var index: usize = 0;
        while (index < input.len) {
            if (input[index] != '<') {
                try self.writeTextUntilTag(input, &index);
                continue;
            }

            const end = std.mem.indexOfScalarPos(u8, input, index, '>') orelse {
                try self.writeTextByte(input[index]);
                index += 1;
                continue;
            };

            const raw_tag = std.mem.trim(u8, input[index + 1 .. end], " \t\r\n");
            index = end + 1;
            if (raw_tag.len == 0 or raw_tag[0] == '!') continue;

            const tag = parseTag(raw_tag);
            if (tag.name.len == 0) continue;

            if (!tag.closing and (equalsIgnoreCase(tag.name, "script") or equalsIgnoreCase(tag.name, "style"))) {
                index = skipRawElement(input, index, tag.name);
                continue;
            }

            try self.handleTag(tag);
        }

        self.trimTrailingWhitespace();
    }

    fn writeTextUntilTag(self: *TextRenderer, input: []const u8, index: *usize) !void {
        while (index.* < input.len and input[index.*] != '<') {
            if (input[index.*] == '&') {
                const semicolon = std.mem.indexOfScalarPos(u8, input, index.*, ';');
                if (semicolon) |end| {
                    if (try writeEntity(&self.out.writer, input[index.* + 1 .. end])) {
                        self.at_line_start = false;
                        self.newline_count = 0;
                        index.* = end + 1;
                        continue;
                    }
                }
            }

            try self.writeTextByte(input[index.*]);
            index.* += 1;
        }
    }

    fn handleTag(self: *TextRenderer, tag: Tag) !void {
        if (equalsIgnoreCase(tag.name, "br")) {
            try self.newline(1);
        } else if (equalsIgnoreCase(tag.name, "p")) {
            try self.newline(2);
        } else if (equalsIgnoreCase(tag.name, "div")) {
            try self.handleDivTag(tag);
        } else if (equalsIgnoreCase(tag.name, "blockquote") or equalsIgnoreCase(tag.name, "gg-markup-quote") or hasClass(tag.raw, "gg-markup-quote") or hasClass(tag.raw, "quote")) {
            if (tag.closing) {
                if (self.quote_depth > 0) self.quote_depth -= 1;
                try self.newline(2);
            } else {
                try self.newline(2);
                self.quote_depth += 1;
            }
        } else if (equalsIgnoreCase(tag.name, "ul") or equalsIgnoreCase(tag.name, "ol")) {
            try self.newline(1);
        } else if (equalsIgnoreCase(tag.name, "li")) {
            if (tag.closing) {
                try self.newline(1);
            } else {
                try self.newline(1);
                try self.writeText("- ");
            }
        } else if (equalsIgnoreCase(tag.name, "a")) {
            if (tag.closing) {
                if (self.active_link) |link| {
                    const link_text = self.out.written()[link.start..];
                    if (linkTextIsUrlPrefix(link_text, link.href)) {
                        self.out.shrinkRetainingCapacity(link.start);
                        try self.writeText(link.href);
                    } else {
                        try self.writeText(" (");
                        try self.writeText(link.href);
                        try self.writeText(")");
                    }
                    self.active_link = null;
                }
            } else {
                if (findAttribute(tag.raw, "href")) |href| {
                    self.active_link = .{
                        .href = href,
                        .start = self.out.written().len,
                    };
                }
            }
        }
    }

    fn handleDivTag(self: *TextRenderer, tag: Tag) !void {
        if (tag.closing) {
            if (self.quote_div_depth_count > 0 and self.quote_div_depths[self.quote_div_depth_count - 1] == self.div_depth) {
                self.quote_div_depth_count -= 1;
                if (self.quote_depth > 0) self.quote_depth -= 1;
                try self.newline(2);
            }
            if (self.div_depth > 0) self.div_depth -= 1;
            return;
        }

        self.div_depth += 1;
        if (hasClass(tag.raw, "gg-markup-quote") or hasClass(tag.raw, "quote")) {
            try self.newline(2);
            self.quote_depth += 1;
            if (self.quote_div_depth_count < self.quote_div_depths.len) {
                self.quote_div_depths[self.quote_div_depth_count] = self.div_depth;
                self.quote_div_depth_count += 1;
            }
        }
    }

    fn writeText(self: *TextRenderer, text: []const u8) !void {
        for (text) |byte| {
            try self.writeTextByte(byte);
        }
    }

    fn writeTextByte(self: *TextRenderer, byte: u8) !void {
        if (byte == '\r') return;
        if (byte == '\n') {
            try self.newline(1);
            return;
        }
        if (std.ascii.isWhitespace(byte)) {
            self.pending_space = !self.at_line_start;
            return;
        }

        try self.writeLinePrefixIfNeeded();
        if (self.pending_space) {
            try self.out.writer.writeByte(' ');
            self.pending_space = false;
        }
        try self.out.writer.writeByte(byte);
        self.at_line_start = false;
        self.newline_count = 0;
    }

    fn newline(self: *TextRenderer, count: usize) !void {
        self.pending_space = false;
        while (self.newline_count < count and self.out.written().len > 0) {
            try self.out.writer.writeByte('\n');
            self.newline_count += 1;
        }
        self.at_line_start = true;
    }

    fn writeLinePrefixIfNeeded(self: *TextRenderer) !void {
        if (!self.at_line_start or self.quote_depth == 0) return;
        for (0..self.quote_depth) |_| {
            try self.out.writer.writeAll(self.options.quote_prefix);
        }
        self.at_line_start = false;
    }

    fn trimTrailingWhitespace(self: *TextRenderer) void {
        while (self.out.written().len > 0) {
            const written = self.out.written();
            const last = written[written.len - 1];
            if (last != ' ' and last != '\n' and last != '\t') break;
            self.out.shrinkRetainingCapacity(written.len - 1);
        }
    }
};

const LinkInfo = struct {
    href: []const u8,
    start: usize,
};

const Tag = struct {
    raw: []const u8,
    name: []const u8,
    closing: bool,
};

fn parseTag(raw: []const u8) Tag {
    var body = raw;
    var closing = false;
    if (body.len > 0 and body[0] == '/') {
        closing = true;
        body = std.mem.trim(u8, body[1..], " \t\r\n");
    }

    var end: usize = 0;
    while (end < body.len and !std.ascii.isWhitespace(body[end]) and body[end] != '/') : (end += 1) {}

    return .{
        .raw = body,
        .name = body[0..end],
        .closing = closing,
    };
}

fn skipRawElement(input: []const u8, start: usize, name: []const u8) usize {
    var index = start;
    while (index < input.len) {
        const tag_start = std.mem.indexOfScalarPos(u8, input, index, '<') orelse return input.len;
        const tag_end = std.mem.indexOfScalarPos(u8, input, tag_start, '>') orelse return input.len;
        const tag = parseTag(std.mem.trim(u8, input[tag_start + 1 .. tag_end], " \t\r\n"));
        if (tag.closing and equalsIgnoreCase(tag.name, name)) return tag_end + 1;
        index = tag_end + 1;
    }
    return input.len;
}

fn hasClass(raw: []const u8, class_name: []const u8) bool {
    const class_value = findAttribute(raw, "class") orelse return false;
    var parts = std.mem.tokenizeAny(u8, class_value, " \t\r\n");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, class_name)) return true;
    }
    return false;
}

fn findAttribute(raw: []const u8, name: []const u8) ?[]const u8 {
    var index: usize = 0;
    while (index < raw.len) {
        while (index < raw.len and !std.ascii.isWhitespace(raw[index])) : (index += 1) {}
        while (index < raw.len and std.ascii.isWhitespace(raw[index])) : (index += 1) {}
        if (index >= raw.len) return null;

        const key_start = index;
        while (index < raw.len and raw[index] != '=' and !std.ascii.isWhitespace(raw[index]) and raw[index] != '/') : (index += 1) {}
        const key = raw[key_start..index];
        while (index < raw.len and std.ascii.isWhitespace(raw[index])) : (index += 1) {}
        if (index >= raw.len or raw[index] != '=') continue;
        index += 1;
        while (index < raw.len and std.ascii.isWhitespace(raw[index])) : (index += 1) {}
        if (index >= raw.len) return null;

        const quote = raw[index];
        const value_start = if (quote == '"' or quote == '\'') index + 1 else index;
        const value_end = if (quote == '"' or quote == '\'')
            std.mem.indexOfScalarPos(u8, raw, value_start, quote) orelse raw.len
        else
            findUnquotedAttributeEnd(raw, value_start);
        index = @min(value_end + 1, raw.len);

        if (equalsIgnoreCase(key, name)) return raw[value_start..value_end];
    }

    return null;
}

fn findUnquotedAttributeEnd(raw: []const u8, start: usize) usize {
    var end = start;
    while (end < raw.len and !std.ascii.isWhitespace(raw[end]) and raw[end] != '/') : (end += 1) {}
    return end;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn linkTextIsUrlPrefix(link_text: []const u8, href: []const u8) bool {
    const text = std.mem.trim(u8, link_text, " \t\r\n");
    const without_ellipsis = if (std.mem.endsWith(u8, text, "...")) text[0 .. text.len - 3] else text;
    return without_ellipsis.len > 0 and std.mem.startsWith(u8, href, without_ellipsis);
}

fn wrapText(allocator: Allocator, text: []const u8, width: usize, quote_prefix: []const u8) ![]u8 {
    if (width == 0) return allocator.dupe(u8, "");

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.writer.writeByte('\n');
        first = false;
        try writeWrappedLine(&out.writer, line, width, quote_prefix);
    }

    return try out.toOwnedSlice();
}

fn writeWrappedLine(writer: *std.Io.Writer, line: []const u8, width: usize, quote_prefix: []const u8) !void {
    const prefix = quoteLinePrefix(line, quote_prefix);
    const body = std.mem.trim(u8, line[prefix.len..], " \t");
    if (body.len == 0) {
        try writer.writeAll(prefix);
        return;
    }

    var state = LineWrapState{
        .writer = writer,
        .width = width,
        .prefix = prefix,
    };

    var index: usize = 0;
    while (index < body.len) {
        while (index < body.len and isInlineWhitespace(body[index])) : (index += 1) {}
        if (index >= body.len) break;

        const start = index;
        while (index < body.len and !isInlineWhitespace(body[index])) : (index += 1) {}
        try state.writeWord(body[start..index]);
    }
}

const LineWrapState = struct {
    writer: *std.Io.Writer,
    width: usize,
    prefix: []const u8,
    line_started: bool = false,
    line_width: usize = 0,

    fn writeWord(self: *LineWrapState, word: []const u8) !void {
        const word_width = displayWidth(word);
        if (!self.line_started) {
            try self.startLine();
        } else if (self.line_width + 1 + word_width <= self.width) {
            try self.writer.writeByte(' ');
            self.line_width += 1;
        } else {
            try self.writer.writeByte('\n');
            self.line_started = false;
            try self.startLine();
        }

        if (word_width <= self.remainingWidth()) {
            try self.writer.writeAll(word);
            self.line_width += word_width;
            return;
        }

        try self.writeLongWord(word);
    }

    fn startLine(self: *LineWrapState) !void {
        try self.writer.writeAll(self.prefix);
        self.line_width = displayWidth(self.prefix);
        self.line_started = true;
    }

    fn remainingWidth(self: LineWrapState) usize {
        if (self.line_width >= self.width) return 0;
        return self.width - self.line_width;
    }

    fn writeLongWord(self: *LineWrapState, word: []const u8) !void {
        var view = std.unicode.Utf8View.init(word) catch {
            try self.writer.writeAll(word);
            self.line_width += word.len;
            return;
        };
        var iter = view.iterator();
        while (iter.nextCodepointSlice()) |slice| {
            const slice_width = displayWidth(slice);
            if (self.line_width > displayWidth(self.prefix) and self.line_width + slice_width > self.width) {
                try self.writer.writeByte('\n');
                self.line_started = false;
                try self.startLine();
            }
            try self.writer.writeAll(slice);
            self.line_width += slice_width;
        }
    }
};

fn quoteLinePrefix(line: []const u8, quote_prefix: []const u8) []const u8 {
    if (quote_prefix.len == 0) return "";

    var end: usize = 0;
    while (std.mem.startsWith(u8, line[end..], quote_prefix)) {
        end += quote_prefix.len;
        if (end >= line.len) break;
    }
    return line[0..end];
}

fn displayWidth(text: []const u8) usize {
    const view = std.unicode.Utf8View.init(text) catch return text.len;
    var iter = view.iterator();

    var width: usize = 0;
    while (iter.nextCodepoint()) |codepoint| {
        width += codepointDisplayWidth(codepoint);
    }
    return width;
}

fn codepointDisplayWidth(codepoint: u21) usize {
    if (codepoint == 0) return 0;
    if (codepoint < 0x20 or (codepoint >= 0x7f and codepoint < 0xa0)) return 0;
    if (codepoint >= 0x300 and codepoint <= 0x36f) return 0;
    if (isWideCodepoint(codepoint)) return 2;
    return 1;
}

fn isWideCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x115f) or
        (codepoint >= 0x2329 and codepoint <= 0x232a) or
        (codepoint >= 0x2e80 and codepoint <= 0xa4cf) or
        (codepoint >= 0xac00 and codepoint <= 0xd7a3) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0xfe10 and codepoint <= 0xfe19) or
        (codepoint >= 0xfe30 and codepoint <= 0xfe6f) or
        (codepoint >= 0xff00 and codepoint <= 0xff60) or
        (codepoint >= 0xffe0 and codepoint <= 0xffe6);
}

fn isInlineWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r';
}

fn linkifyUrls(allocator: Allocator, text: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var index: usize = 0;
    while (index < text.len) {
        const next_http = std.mem.indexOfPos(u8, text, index, "http://");
        const next_https = std.mem.indexOfPos(u8, text, index, "https://");
        const start = minOptionalIndex(next_http, next_https) orelse {
            try out.writer.writeAll(text[index..]);
            break;
        };

        try out.writer.writeAll(text[index..start]);
        var end = start;
        while (end < text.len and !std.ascii.isWhitespace(text[end]) and text[end] != ')') : (end += 1) {}
        var url_end = end;
        while (url_end > start and isTrailingUrlPunctuation(text[url_end - 1])) : (url_end -= 1) {}

        const url = text[start..url_end];
        try writeOsc8Link(&out.writer, url);
        try out.writer.writeAll(text[url_end..end]);
        index = end;
    }

    return try out.toOwnedSlice();
}

fn minOptionalIndex(a: ?usize, b: ?usize) ?usize {
    if (a) |left| {
        if (b) |right| return @min(left, right);
        return left;
    }
    return b;
}

fn isTrailingUrlPunctuation(byte: u8) bool {
    return byte == '.' or byte == ',' or byte == ';' or byte == ':' or byte == '!' or byte == '?';
}

fn writeOsc8Link(writer: *std.Io.Writer, url: []const u8) !void {
    try writer.writeAll("\x1b]8;;");
    try writer.writeAll(url);
    try writer.writeAll("\x1b\\");
    try writer.writeAll(url);
    try writer.writeAll("\x1b]8;;\x1b\\");
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

test "convert paragraphs and line breaks to text" {
    const text = try toText(std.testing.allocator, "<p>First&nbsp;line<br>Second line</p><p>Next</p>", .{});
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("First line\nSecond line\n\nNext", text);
}

test "convert blockquote and BGG quote markup to quoted text" {
    const text = try toText(
        std.testing.allocator,
        "<blockquote>Quoted<br>line</blockquote><div class=\"gg-markup-quote\">BGG quote</div>",
        .{},
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("> Quoted\n> line\n\n> BGG quote", text);
}

test "convert lists and links to readable text" {
    const text = try toText(
        std.testing.allocator,
        "<ul><li>One</li><li><a href=\"https://example.test/game\">Two</a></li></ul>",
        .{},
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("- One\n- Two (https://example.test/game)", text);
}

test "skip script and style content" {
    const text = try toText(
        std.testing.allocator,
        "Visible<script>alert('x')</script><style>.x{}</style> text",
        .{},
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Visible text", text);
}

test "avoid duplicating anchor href when link text is url" {
    const text = try toText(
        std.testing.allocator,
        "<a href=\"https://example.com/very/long/path\">https://example.com/very/lon...</a>",
        .{},
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("https://example.com/very/long/path", text);
}

test "wrap html text while preserving quote prefix" {
    const text = try toText(
        std.testing.allocator,
        "<blockquote>The quick brown fox jumps over the lazy dog</blockquote>",
        .{ .quote_prefix = "| ", .wrap_width = 20 },
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("| The quick brown\n| fox jumps over the\n| lazy dog", text);
}

test "linkify plain urls with osc8 hyperlinks" {
    const text = try toText(
        std.testing.allocator,
        "Visit https://example.com.",
        .{ .linkify_urls = true },
    );
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "\x1b]8;;https://example.com\x1b\\") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "\x1b]8;;\x1b\\."));
}

test "convert bgg quote div format" {
    const text = try toText(
        std.testing.allocator,
        "<div class='quote'><div class='quotetitle'><p><b>user wrote:</b></p></div><div class='quotebody'><i>quoted text</i></div></div>rest",
        .{ .quote_prefix = "| " },
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("| user wrote:\n\n| quoted text\n\nrest", text);
}
