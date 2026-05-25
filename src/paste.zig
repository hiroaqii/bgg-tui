const std = @import("std");

pub fn insertCodepoints(input: anytype, text: []const u8) !void {
    var index: usize = 0;
    while (index < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[index]) catch {
            index += 1;
            continue;
        };
        if (index + len > text.len) break;

        const codepoint = std.unicode.utf8Decode(text[index .. index + len]) catch {
            index += len;
            continue;
        };
        if (isCodepointAllowed(codepoint)) {
            try input.update(.{ .insert = codepoint });
        }
        index += len;
    }
}

pub fn isCodepointAllowed(codepoint: u21) bool {
    return codepoint >= 0x20 and codepoint != 0x7f and !(codepoint >= 0x80 and codepoint <= 0x9f);
}
