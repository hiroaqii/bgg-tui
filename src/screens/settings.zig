const std = @import("std");
const chasen = @import("chasen");
const ui = @import("chasen_ui");

const config_mod = @import("../config.zig");

const Kind = enum {
    text,
    cycle,
    toggle,
    info,
};

const Item = struct {
    label: []const u8 = "",
    section: []const u8 = "",
    kind: Kind,
};

pub const EditField = enum {
    token,
    username,
    list_width,
    thread_width,
    detail_width,
};

const items = [_]Item{
    .{ .label = "Color Theme", .section = "Interface", .kind = .cycle },
    .{ .label = "Transition", .kind = .cycle },
    .{ .label = "Selection", .kind = .cycle },
    .{ .label = "Border Style", .kind = .cycle },
    .{ .label = "List Density", .kind = .cycle },
    .{ .label = "Date Format", .kind = .cycle },
    .{ .label = "Show Images", .section = "Display", .kind = .toggle },
    .{ .label = "List Width", .kind = .text },
    .{ .label = "Thread Width", .kind = .text },
    .{ .label = "Detail Width", .kind = .text },
    .{ .label = "Default Username", .section = "Collection", .kind = .text },
    .{ .label = "Token", .section = "API", .kind = .text },
    .{ .section = "Config File", .kind = .info },
};

/// Size needed to show the Go-compatible settings shell: title, section gaps,
/// all rows through Config File, and the in-content help line.
pub const required_size = chasen.Size{ .width = 72, .height = 26 };

pub const State = struct {
    list: ui.List = ui.List.init(.{ .items = itemLabels() }),
    editing: ?EditField = null,

    pub fn updateList(self: *State, msg: ui.List.Msg) void {
        self.list.update(msg);
    }

    pub fn startEdit(self: *State, field: EditField) void {
        self.editing = field;
    }

    pub fn stopEditing(self: *State) void {
        self.editing = null;
    }

    pub fn focusedEditField(self: *const State) ?EditField {
        return switch (self.list.focusedIndex()) {
            list_width_index => .list_width,
            thread_width_index => .thread_width,
            detail_width_index => .detail_width,
            username_index => .username,
            token_index => .token,
            else => null,
        };
    }

    pub fn isShowImagesFocused(self: *const State) bool {
        return self.list.focusedIndex() == show_images_index;
    }

    pub fn handleEvent(self: *const State, event: chasen.Event) ?ui.List.Msg {
        if (event == .key_press) {
            if (event.key_press.codepoint == 'k') return .move_prev;
            if (event.key_press.codepoint == 'j') return .move_next;
        }
        return self.list.handleEvent(event);
    }

    pub fn view(
        self: *const State,
        surface: *chasen.Surface,
        config: config_mod.Config,
        config_path: ?[]const u8,
        token_input: ?*const ui.PasswordInput,
        username_input: ?*const ui.TextInput,
        width_input: ?*const ui.TextInput,
    ) !void {
        const size = surface.size();
        if (size.width == 0 or size.height == 0) return;

        if (self.editing == null) surface.hideCursor();
        _ = surface.borrowTextAt(0, 0, "Settings", .{ .bold = true, .fg = .{ .index = 14 } });

        var row: u16 = 2;
        var current_section: []const u8 = "";
        for (items, 0..) |item, index| {
            if (item.section.len > 0) {
                current_section = item.section;
                if (index > 0) row += 1;
                if (row >= size.height) return;
                _ = surface.borrowTextAt(0, row, item.section, .{ .fg = .gray });
                row += 1;
            }
            if (row >= size.height) return;

            try drawItem(surface, row, index, item, current_section, config, config_path, self.list.focus.isFocused(index), self.editing, token_input, username_input, width_input);
            row += 1;
        }

        if (row < size.height) {
            const help = if (self.editing != null)
                "Enter: Save  Esc: Cancel"
            else if (self.focusedEditField()) |field|
                editHelp(field)
            else if (self.isShowImagesFocused())
                "j/k ↑↓: Navigate  Enter: Toggle Images  m: Menu  Esc/q: Quit"
            else
                "j/k ↑↓: Navigate  m: Menu  Esc/q: Quit";
            _ = surface.borrowTextAt(0, row +| 1, help, .{ .dim = true });
        }
    }
};

fn drawItem(
    surface: *chasen.Surface,
    row: u16,
    index: usize,
    item: Item,
    section: []const u8,
    config: config_mod.Config,
    config_path: ?[]const u8,
    focused: bool,
    editing: ?EditField,
    token_input: ?*const ui.PasswordInput,
    username_input: ?*const ui.TextInput,
    width_input: ?*const ui.TextInput,
) !void {
    const label_style: chasen.TextStyle = if (focused) .{ .bold = true, .fg = .{ .index = 14 } } else .{};
    const cursor = if (focused) "> " else "  ";

    _ = surface.borrowTextAt(0, row, cursor, .{ .dim = !focused });
    const value = try valueFor(surface, index, config, config_path);

    if (item.label.len == 0) {
        _ = surface.borrowTextAt(2, row, value, label_style);
        return;
    }

    _ = surface.borrowTextAt(2, row, item.label, label_style);
    const value_col: u16 = @intCast(2 + sectionWidth(section) + 2);
    _ = surface.borrowTextAt(value_col - 2, row, ":", .{});
    if (drawEditingInput(surface, row, value_col, index, editing, token_input, username_input, width_input)) {
        return;
    }
    switch (item.kind) {
        .cycle, .toggle => {
            _ = surface.borrowTextAt(value_col, row, "[", .{});
            _ = surface.borrowTextAt(value_col + 1, row, value, .{});
            _ = surface.borrowTextAt(value_col + 1 + chasen.text.displayWidth(value), row, "]", .{});
        },
        .text, .info => _ = surface.borrowTextAt(value_col, row, value, .{}),
    }
}

fn drawEditingInput(
    surface: *chasen.Surface,
    row: u16,
    col: u16,
    index: usize,
    editing: ?EditField,
    token_input: ?*const ui.PasswordInput,
    username_input: ?*const ui.TextInput,
    width_input: ?*const ui.TextInput,
) bool {
    const field = editing orelse return false;
    const input_rect = chasen.Rect{
        .col = col,
        .row = row,
        .width = surface.size().width -| col,
        .height = 1,
    };
    switch (field) {
        .token => {
            if (index != token_index) return false;
            if (token_input) |input| {
                var input_area = surface.child(input_rect);
                input.view(&input_area, .{});
            }
            return true;
        },
        .username => {
            if (index != username_index) return false;
            if (username_input) |input| {
                var input_area = surface.child(input_rect);
                input.view(&input_area, .{});
            }
            return true;
        },
        .list_width, .thread_width, .detail_width => {
            if (index != fieldIndex(field)) return false;
            if (width_input) |input| {
                var input_area = surface.child(input_rect);
                input.view(&input_area, .{});
            }
            return true;
        },
    }
}

fn editHelp(field: EditField) []const u8 {
    return switch (field) {
        .token => "j/k ↑↓: Navigate  Enter: Edit Token  m: Menu  Esc/q: Quit",
        .username => "j/k ↑↓: Navigate  Enter: Edit Username  m: Menu  Esc/q: Quit",
        .list_width => "j/k ↑↓: Navigate  Enter: Edit List Width  m: Menu  Esc/q: Quit",
        .thread_width => "j/k ↑↓: Navigate  Enter: Edit Thread Width  m: Menu  Esc/q: Quit",
        .detail_width => "j/k ↑↓: Navigate  Enter: Edit Detail Width  m: Menu  Esc/q: Quit",
    };
}

fn fieldIndex(field: EditField) usize {
    return switch (field) {
        .list_width => list_width_index,
        .thread_width => thread_width_index,
        .detail_width => detail_width_index,
        .username => username_index,
        .token => token_index,
    };
}

const list_width_index: usize = 7;
const thread_width_index: usize = 8;
const detail_width_index: usize = 9;
const username_index: usize = 10;
const token_index: usize = 11;
const show_images_index: usize = 6;

fn valueFor(surface: *chasen.Surface, index: usize, config: config_mod.Config, config_path: ?[]const u8) ![]const u8 {
    return switch (index) {
        0 => config.interface.color_theme,
        1 => config.interface.transition,
        2 => config.interface.selection,
        3 => config.interface.border_style,
        4 => config.interface.list_density,
        5 => config.interface.date_format,
        6 => if (config.display.show_images) "ON" else "OFF",
        7 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.list_width}),
        8 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.thread_width}),
        9 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.detail_width}),
        10 => config.collection.default_username orelse "(not set)",
        11 => try maskedToken(surface, config.apiClientToken()),
        12 => config_path orelse "(unknown)",
        else => "",
    };
}

fn maskedToken(surface: *chasen.Surface, token: ?[]const u8) ![]const u8 {
    const value = token orelse return "(not set)";
    if (value.len <= 8) {
        return try repeated(surface, '*', value.len);
    }
    const middle_len = value.len - 8;
    return try std.fmt.allocPrint(surface.frameAllocator(), "{s}{s}{s}", .{
        value[0..4],
        try repeated(surface, '*', middle_len),
        value[value.len - 4 ..],
    });
}

fn repeated(surface: *chasen.Surface, byte: u8, len: usize) ![]const u8 {
    const out = try surface.frameAllocator().alloc(u8, len);
    @memset(out, byte);
    return out;
}

fn sectionWidth(section: []const u8) usize {
    if (std.mem.eql(u8, section, "Interface")) return 12;
    if (std.mem.eql(u8, section, "Display")) return 12;
    if (std.mem.eql(u8, section, "Collection")) return 16;
    if (std.mem.eql(u8, section, "API")) return 5;
    return 0;
}

fn itemLabels() []const []const u8 {
    comptime {
        var labels: [items.len][]const u8 = undefined;
        for (items, 0..) |item, index| {
            labels[index] = item.label;
        }
        const final = labels;
        return &final;
    }
}

test "settings state exposes the configured settings rows" {
    const state: State = .{};

    try std.testing.expectEqual(@as(usize, 13), state.list.items.len);
    try std.testing.expectEqualStrings("Color Theme", state.list.items[0]);
    try std.testing.expectEqualStrings("", state.list.items[state.list.items.len - 1]);
}

test "settings list movement is delegated to ui.List" {
    var state: State = .{};

    state.updateList(.move_next);
    try std.testing.expectEqual(@as(usize, 1), state.list.focusedIndex());
    state.updateList(.move_prev);
    try std.testing.expectEqual(@as(usize, 0), state.list.focusedIndex());
}

test "settings focused edit field follows editable rows" {
    var state: State = .{};

    try std.testing.expect(state.focusedEditField() == null);
    for (0..username_index) |_| state.updateList(.move_next);
    try std.testing.expectEqual(EditField.username, state.focusedEditField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(EditField.token, state.focusedEditField().?);
}

test "settings focused edit field includes width rows" {
    var state: State = .{};

    for (0..list_width_index) |_| state.updateList(.move_next);
    try std.testing.expectEqual(EditField.list_width, state.focusedEditField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(EditField.thread_width, state.focusedEditField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(EditField.detail_width, state.focusedEditField().?);
}

test "settings exposes show images focused row" {
    var state: State = .{};

    for (0..show_images_index) |_| state.updateList(.move_next);

    try std.testing.expect(state.isShowImagesFocused());
    try std.testing.expect(state.focusedEditField() == null);
}
