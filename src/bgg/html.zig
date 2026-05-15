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
    if (std.mem.eql(u8, entity, "amp")) {
        try writer.writeByte('&');
    } else if (std.mem.eql(u8, entity, "apos")) {
        try writer.writeByte('\'');
    } else if (std.mem.eql(u8, entity, "quot")) {
        try writer.writeByte('"');
    } else if (std.mem.eql(u8, entity, "lt")) {
        try writer.writeByte('<');
    } else if (std.mem.eql(u8, entity, "gt")) {
        try writer.writeByte('>');
    } else if (std.mem.eql(u8, entity, "nbsp")) {
        try writer.writeByte(' ');
    } else if (std.mem.startsWith(u8, entity, "#x") or std.mem.startsWith(u8, entity, "#X")) {
        try writeCodepoint(writer, std.fmt.parseInt(u21, entity[2..], 16) catch return false);
    } else if (std.mem.startsWith(u8, entity, "#")) {
        try writeCodepoint(writer, std.fmt.parseInt(u21, entity[1..], 10) catch return false);
    } else {
        return false;
    }

    return true;
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
