const std = @import("std");
const anim = @import("chasen_anim");

const default_frames: u64 = 84;

const Spec = struct {
    value: []const u8,
    kind: anim.TransitionKind,
    frames: u64,
    selectable: bool = true,
    random_candidate: bool = true,
};

const specs = [_]Spec{
    .{ .value = "none", .kind = .none, .frames = 0, .random_candidate = false },
    .{ .value = "fade", .kind = .fade, .frames = default_frames },
    .{ .value = "glitch", .kind = .glitch, .frames = 192 },
    .{ .value = "code-rain", .kind = .code_rain, .frames = 96 },
    .{ .value = "dissolve", .kind = .dissolve, .frames = 60 },
    .{ .value = "sweep", .kind = .sweep, .frames = default_frames },
    .{ .value = "spiral", .kind = .spiral, .frames = 104 },
    .{ .value = "warp", .kind = .warp, .frames = 96 },
    .{ .value = "scanline", .kind = .scanline, .frames = 110 },
    .{ .value = "iris", .kind = .iris, .frames = 90 },
    .{ .value = "shutter", .kind = .shutter, .frames = 72 },
    .{ .value = "lines", .kind = .lines, .frames = 90 },
    .{ .value = "lines-cross", .kind = .lines_cross, .frames = 90 },
    .{ .value = "random", .kind = .none, .frames = 0, .random_candidate = false },
};

pub const values = selectableValues();
pub const random_candidates = randomCandidates();

pub fn isValidValue(value: []const u8) bool {
    return specForValue(value) != null;
}

pub fn kindForValue(value: []const u8) anim.TransitionKind {
    if (specForValue(value)) |spec| return spec.kind;
    return .none;
}

pub fn kindForConfig(value: []const u8, seed: u64) anim.TransitionKind {
    if (std.mem.eql(u8, value, "random")) return randomKind(seed);
    return kindForValue(value);
}

pub fn framesForKind(kind: anim.TransitionKind) u64 {
    for (specs) |spec| {
        if (spec.kind == kind and spec.kind != .none) return spec.frames;
    }
    return default_frames;
}

pub fn randomKind(seed: u64) anim.TransitionKind {
    return random_candidates[choiceHash(seed) % random_candidates.len];
}

fn specForValue(value: []const u8) ?Spec {
    for (specs) |spec| {
        if (!spec.selectable) continue;
        if (std.mem.eql(u8, value, spec.value)) return spec;
    }
    return null;
}

fn selectableValues() [selectableCount()][]const u8 {
    var result: [selectableCount()][]const u8 = undefined;
    var index: usize = 0;
    for (specs) |spec| {
        if (!spec.selectable) continue;
        result[index] = spec.value;
        index += 1;
    }
    return result;
}

fn selectableCount() usize {
    var count: usize = 0;
    for (specs) |spec| {
        if (spec.selectable) count += 1;
    }
    return count;
}

fn randomCandidates() [randomCandidateCount()]anim.TransitionKind {
    var result: [randomCandidateCount()]anim.TransitionKind = undefined;
    var index: usize = 0;
    for (specs) |spec| {
        if (!spec.random_candidate) continue;
        result[index] = spec.kind;
        index += 1;
    }
    return result;
}

fn randomCandidateCount() usize {
    var count: usize = 0;
    for (specs) |spec| {
        if (spec.random_candidate) count += 1;
    }
    return count;
}

fn choiceHash(seed: u64) usize {
    var value = seed +% 0x9e37_79b9_7f4a_7c15;
    value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
    return @intCast(value ^ (value >> 31));
}

test "selectable transition values stay in settings order" {
    try std.testing.expectEqualStrings("none", values[0]);
    try std.testing.expectEqualStrings("fade", values[1]);
    try std.testing.expectEqualStrings("random", values[values.len - 1]);
}

test "removed wipe transition remains unsupported" {
    try std.testing.expect(!isValidValue("wipe"));
    try std.testing.expectEqual(anim.TransitionKind.none, kindForValue("wipe"));
}

test "random candidates exclude none and random" {
    for (random_candidates) |kind| {
        try std.testing.expect(kind != .none);
    }
}
