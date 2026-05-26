const std = @import("std");
const chasen = @import("chasen");
const anim = @import("chasen_anim");
const ui = @import("chasen_ui");

const config_mod = @import("../config.zig");
const motion = @import("../motion.zig");
const style_mod = @import("../style.zig");
const transitions = @import("../transitions.zig");

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

pub const CycleField = enum {
    color_theme,
    transition,
    selection,
    border_style,
    list_density,
    date_format,
    image_protocol,
};

pub const Msg = union(enum) {
    token_start,
    token_input: ui.PasswordInput.Msg,
    token_paste: []const u8,
    token_submit,
    token_cancel,
    username_start,
    username_input: ui.TextInput.Msg,
    username_paste: []const u8,
    username_submit,
    username_cancel,
    width_start: EditField,
    width_input: ui.TextInput.Msg,
    width_paste: []const u8,
    width_submit,
    width_cancel,
    show_images_toggle,
    cycle_next: CycleField,
    picker_open: CycleField,
    picker_move_prev,
    picker_move_next,
    picker_confirm,
    picker_cancel,
    list: ui.List.Msg,
};

pub const PickerState = struct {
    field: CycleField,
    committed_index: usize,
    preview_index: usize,
    preview_started_frame: u64,
};

pub const color_theme_values = [_][]const u8{ "default", "blue", "orange", "mono", "matcha" };
pub const transition_values = transitions.values;
pub const selection_values = [_][]const u8{ "none", "invert", "wave", "blink", "glitch", "scan" };
pub const border_style_values = [_][]const u8{ "none", "rounded", "thick", "double", "block", "dots" };
pub const list_density_values = [_][]const u8{ "compact", "normal", "comfortable", "relaxed" };
pub const date_format_values = [_][]const u8{ "yyyy-mm-dd", "yyyy/mm/dd", "relative", "YYYY-MM-DD" };

const items = [_]Item{
    .{ .label = "Color Theme", .section = "Interface", .kind = .cycle },
    .{ .label = "Transition", .kind = .cycle },
    .{ .label = "Selection", .kind = .cycle },
    .{ .label = "Border Style", .kind = .cycle },
    .{ .label = "List Density", .kind = .cycle },
    .{ .label = "Date Format", .kind = .cycle },
    .{ .label = "Show Images", .section = "Display", .kind = .toggle },
    .{ .label = "Image Protocol", .kind = .cycle },
    .{ .label = "List Width", .kind = .text },
    .{ .label = "Thread Width", .kind = .text },
    .{ .label = "Detail Width", .kind = .text },
    .{ .label = "Default Username", .section = "Collection", .kind = .text },
    .{ .label = "Token", .section = "API", .kind = .text },
    .{ .section = "Config File", .kind = .info },
};

/// Size needed to show the Go-compatible settings shell: title, section gaps,
/// all rows through Config File, and the in-content help line.
pub const required_size = chasen.Size{ .width = 72, .height = 27 };

pub const State = struct {
    list: ui.List = ui.List.init(.{ .items = itemLabels() }),
    editing: ?EditField = null,
    token_input: ?ui.PasswordInput = null,
    username_input: ?ui.TextInput = null,
    width_input: ?ui.TextInput = null,
    picker: ?PickerState = null,

    pub fn initInputs(self: *State, allocator: std.mem.Allocator, default_username: ?[]const u8) !void {
        self.token_input = try ui.PasswordInput.init(allocator, .{
            .placeholder = "Enter API token",
        });
        errdefer {
            self.token_input.?.deinit();
            self.token_input = null;
        }
        self.username_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Enter BGG username",
            .value = default_username orelse "",
        });
        errdefer {
            self.username_input.?.deinit();
            self.username_input = null;
        }
        self.width_input = try ui.TextInput.init(allocator, .{
            .placeholder = "Enter width (20-240)",
        });
    }

    pub fn deinitInputs(self: *State) void {
        if (self.token_input) |*input| {
            input.deinit();
            self.token_input = null;
        }
        if (self.username_input) |*input| {
            input.deinit();
            self.username_input = null;
        }
        if (self.width_input) |*input| {
            input.deinit();
            self.width_input = null;
        }
    }

    pub fn updateList(self: *State, msg: ui.List.Msg) void {
        self.list.update(msg);
    }

    pub fn startEdit(self: *State, field: EditField) void {
        self.editing = field;
        self.picker = null;
    }

    pub fn stopEditing(self: *State) void {
        self.editing = null;
    }

    pub fn openPicker(self: *State, field: CycleField, config: config_mod.Config, animation_frame: u64) void {
        const index = pickerIndexFor(field, config) orelse return;
        self.editing = null;
        self.picker = .{
            .field = field,
            .committed_index = index,
            .preview_index = index,
            .preview_started_frame = animation_frame,
        };
    }

    pub fn closePicker(self: *State) void {
        self.picker = null;
    }

    pub fn movePickerPrev(self: *State, animation_frame: u64) void {
        if (self.picker) |*picker| {
            if (picker.preview_index > 0) {
                picker.preview_index -= 1;
                picker.preview_started_frame = animation_frame;
            }
        }
    }

    pub fn movePickerNext(self: *State, animation_frame: u64) void {
        if (self.picker) |*picker| {
            const values = pickerValues(picker.field) orelse return;
            if (picker.preview_index + 1 < values.len) {
                picker.preview_index += 1;
                picker.preview_started_frame = animation_frame;
            }
        }
    }

    pub fn pickerSelectedValue(self: *const State) ?[]const u8 {
        const picker = self.picker orelse return null;
        const values = pickerValues(picker.field) orelse return null;
        if (picker.preview_index >= values.len) return null;
        return values[picker.preview_index];
    }

    pub fn previewConfig(self: *const State, config: config_mod.Config) config_mod.Config {
        var effective = config;
        const picker = self.picker orelse return effective;
        switch (picker.field) {
            .color_theme => {
                if (self.pickerSelectedValue()) |value| effective.interface.color_theme = value;
            },
            .transition => {},
            .selection => {
                if (self.pickerSelectedValue()) |value| effective.interface.selection = value;
            },
            .border_style => {
                if (self.pickerSelectedValue()) |value| effective.interface.border_style = value;
            },
            .list_density => {
                if (self.pickerSelectedValue()) |value| effective.interface.list_density = value;
            },
            .date_format => {
                if (self.pickerSelectedValue()) |value| effective.interface.date_format = value;
            },
            else => {},
        }
        return effective;
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

    pub fn focusedCycleField(self: *const State) ?CycleField {
        return switch (self.list.focusedIndex()) {
            color_theme_index => .color_theme,
            transition_index => .transition,
            selection_index => .selection,
            border_style_index => .border_style,
            list_density_index => .list_density,
            date_format_index => .date_format,
            image_protocol_index => .image_protocol,
            else => null,
        };
    }

    pub fn isShowImagesFocused(self: *const State) bool {
        return self.list.focusedIndex() == show_images_index;
    }

    pub fn pickerOpen(self: *const State) bool {
        return self.picker != null;
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
        theme: style_mod.Theme,
        selection: []const u8,
        animation_frame: u64,
    ) !void {
        const size = surface.size();
        if (size.width == 0 or size.height == 0) return;

        if (self.editing == null) surface.hideCursor();
        _ = surface.borrowTextAt(0, 0, "Settings", theme.title);

        var row: u16 = 2;
        var current_section: []const u8 = "";
        for (items, 0..) |item, index| {
            if (item.section.len > 0) {
                current_section = item.section;
                if (index > 0) row += 1;
                if (row >= size.height) return;
                _ = surface.borrowTextAt(0, row, item.section, theme.muted);
                row += 1;
            }
            if (row >= size.height) return;

            const token_input = if (self.token_input) |*input| input else null;
            const username_input = if (self.username_input) |*input| input else null;
            const width_input = if (self.width_input) |*input| input else null;
            try drawItem(surface, row, index, item, current_section, config, config_path, theme, selection, animation_frame, self.list.focus.isFocused(index), self.editing, token_input, username_input, width_input);
            row += 1;
        }

        if (row < size.height) {
            const help = if (self.picker != null)
                "j/k ↑↓: Choose  Enter: Save  Esc: Cancel"
            else if (self.editing != null)
                "Enter: Save  Esc: Cancel"
            else if (self.focusedEditField()) |field|
                editHelp(field)
            else if (self.focusedCycleField()) |field|
                cycleHelp(field)
            else if (self.isShowImagesFocused())
                "j/k ↑↓: Navigate  Enter: Toggle Images  m: Menu  Esc/q: Quit"
            else
                "j/k ↑↓: Navigate  m: Menu  Esc/q: Quit";
            _ = surface.borrowTextAt(0, row +| 1, help, theme.subtle);
        }

        self.drawPicker(surface, theme, animation_frame);
    }

    fn drawPicker(self: *const State, surface: *chasen.Surface, theme: style_mod.Theme, animation_frame: u64) void {
        const picker = self.picker orelse return;
        const values = pickerValues(picker.field) orelse return;
        const size = surface.size();
        if (size.width < 34 or size.height < 12) return;

        const width: u16 = if (picker.field == .transition) 44 else 30;
        if (size.width < width) return;
        const desired_height = if (picker.field == .transition) values.len + 12 else @min(@as(usize, 10), values.len + 4);
        const height: u16 = @intCast(@min(desired_height, @as(usize, size.height -| 2)));
        const rect = chasen.Rect{
            .col = (size.width - width) / 2,
            .row = @min(@as(u16, 5), size.height - height),
            .width = width,
            .height = height,
        };
        surface.clear(rect);
        var picker_area = surface.child(rect);
        const selected_value = self.pickerSelectedValue() orelse "";
        const frame = ui.Panel.frame(&picker_area, .{
            .title = pickerTitle(picker.field),
            .border = style_mod.borderFromName(selected_value),
            .border_style = theme.border,
            .title_style = theme.title,
        });
        frame.view();

        var content = frame.contentSurface();
        var list_start_row: u16 = 0;
        if (picker.field == .transition) {
            drawTransitionPreview(&content, selected_value, picker.preview_started_frame, animation_frame, theme);
            list_start_row = 10;
        }
        for (values, 0..) |value, index| {
            const row: u16 = list_start_row + @as(u16, @intCast(index));
            if (row >= content.size().height) break;
            const focused = picker.preview_index == index;
            const committed = picker.committed_index == index;
            const cursor = if (focused) "> " else "  ";
            const marker = if (committed) "*" else " ";
            _ = content.borrowTextAt(0, row, cursor, .{ .bold = focused });
            _ = content.borrowTextAt(2, row, marker, if (committed) .{ .fg = theme.accent } else theme.muted);
            const selection = if (picker.field == .selection) selected_value else "none";
            drawItemText(&content, 4, row, value, if (focused) theme.focused else .{}, focused, selection, animation_frame);
        }
    }
};

pub fn pickerValues(field: CycleField) ?[]const []const u8 {
    return switch (field) {
        .color_theme => &color_theme_values,
        .transition => &transition_values,
        .selection => &selection_values,
        .border_style => &border_style_values,
        .list_density => &list_density_values,
        .date_format => &date_format_values,
        else => null,
    };
}

pub fn pickerIndexFor(field: CycleField, config: config_mod.Config) ?usize {
    const current = switch (field) {
        .color_theme => config.interface.color_theme,
        .transition => config.interface.transition,
        .selection => config.interface.selection,
        .border_style => config.interface.border_style,
        .list_density => config.interface.list_density,
        .date_format => config.interface.date_format,
        else => return null,
    };
    const values = pickerValues(field) orelse return null;
    for (values, 0..) |value, index| {
        if (std.mem.eql(u8, current, value)) return index;
    }
    return 0;
}

fn pickerTitle(field: CycleField) []const u8 {
    return switch (field) {
        .color_theme => "Color Theme",
        .transition => "Transition",
        .selection => "Selection",
        .border_style => "Border Style",
        .list_density => "List Density",
        .date_format => "Date Format",
        else => "Setting",
    };
}

fn drawTransitionPreview(surface: *chasen.Surface, value: []const u8, started_frame: u64, animation_frame: u64, theme: style_mod.Theme) void {
    const size = surface.size();
    if (size.width == 0 or size.height < 9) return;

    const preview_height: u16 = 9;
    const preview_rect = chasen.Rect{
        .col = 0,
        .row = 0,
        .width = size.width,
        .height = @min(preview_height, size.height),
    };
    var preview = surface.child(preview_rect);
    preview.clear(.{ .col = 0, .row = 0, .width = preview_rect.width, .height = preview_rect.height });
    _ = preview.borrowTextAt(1, 0, "Transition preview", theme.muted);
    if (preview_rect.height > 1) _ = preview.borrowTextAt(1, 1, "BoardGameGeek", theme.title);
    if (preview_rect.height > 2) _ = preview.borrowTextAt(1, 2, "Hot Games -> Detail", theme.subtle);
    if (preview_rect.height > 3) _ = preview.borrowTextAt(1, 3, "  #   title              rank", theme.muted);
    if (preview_rect.height > 4) _ = preview.borrowTextAt(1, 4, "  1   CATAN              1", theme.subtle);
    if (preview_rect.height > 5) _ = preview.borrowTextAt(1, 5, "  2   Ark Nova           2", theme.subtle);
    if (preview_rect.height > 6) _ = preview.borrowTextAt(1, 6, "  3   Brass Birmingham   3", theme.subtle);
    if (preview_rect.height > 7) _ = preview.borrowTextAt(1, 7, "  4   Dune Imperium      4", theme.subtle);
    if (preview_rect.height > 8) _ = preview.borrowTextAt(1, 8, "  5   Wingspan           5", theme.subtle);

    const kind = transitions.kindForConfig(value, started_frame);
    if (kind == .none) return;

    const max_frame = transitions.framesForKind(kind);
    const elapsed = animation_frame -| started_frame;
    const frame = if (max_frame == 0) 0 else (elapsed % max_frame) + 1;
    motion.applyScreenTransition(&preview, anim.Transition{
        .kind = kind,
        .frame = frame,
        .max_frame = max_frame,
    });
}

fn drawItem(
    surface: *chasen.Surface,
    row: u16,
    index: usize,
    item: Item,
    section: []const u8,
    config: config_mod.Config,
    config_path: ?[]const u8,
    theme: style_mod.Theme,
    selection: []const u8,
    animation_frame: u64,
    focused: bool,
    editing: ?EditField,
    token_input: ?*const ui.PasswordInput,
    username_input: ?*const ui.TextInput,
    width_input: ?*const ui.TextInput,
) !void {
    const label_style: chasen.TextStyle = if (focused) theme.focused else .{};
    const cursor = if (focused) "> " else "  ";

    _ = surface.borrowTextAt(0, row, cursor, .{ .dim = !focused });
    const value = try valueFor(surface, index, config, config_path);

    if (item.label.len == 0) {
        drawItemText(surface, 2, row, value, label_style, focused, selection, animation_frame);
        return;
    }

    drawItemText(surface, 2, row, item.label, label_style, focused, selection, animation_frame);
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

fn drawItemText(surface: *chasen.Surface, col: u16, row: u16, text: []const u8, style: chasen.TextStyle, focused: bool, selection: []const u8, animation_frame: u64) void {
    if (focused) {
        motion.drawFocusedText(surface, col, row, text, style, selection, animation_frame);
    } else {
        _ = surface.borrowTextAt(col, row, text, style);
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

fn cycleHelp(field: CycleField) []const u8 {
    return switch (field) {
        .color_theme => "j/k ↑↓: Navigate  Enter: Change Color Theme  m: Menu  Esc/q: Quit",
        .transition => "j/k ↑↓: Navigate  Enter: Change Transition  m: Menu  Esc/q: Quit",
        .selection => "j/k ↑↓: Navigate  Enter: Change Selection  m: Menu  Esc/q: Quit",
        .border_style => "j/k ↑↓: Navigate  Enter: Change Border Style  m: Menu  Esc/q: Quit",
        .list_density => "j/k ↑↓: Navigate  Enter: Change List Density  m: Menu  Esc/q: Quit",
        .date_format => "j/k ↑↓: Navigate  Enter: Change Date Format  m: Menu  Esc/q: Quit",
        .image_protocol => "j/k ↑↓: Navigate  Enter: Change Image Protocol  m: Menu  Esc/q: Quit",
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

const show_images_index: usize = 6;
const image_protocol_index: usize = 7;
const list_width_index: usize = 8;
const thread_width_index: usize = 9;
const detail_width_index: usize = 10;
const username_index: usize = 11;
const token_index: usize = 12;
const color_theme_index: usize = 0;
const transition_index: usize = 1;
const selection_index: usize = 2;
const border_style_index: usize = 3;
const list_density_index: usize = 4;
const date_format_index: usize = 5;

fn valueFor(surface: *chasen.Surface, index: usize, config: config_mod.Config, config_path: ?[]const u8) ![]const u8 {
    return switch (index) {
        0 => config.interface.color_theme,
        1 => config.interface.transition,
        2 => config.interface.selection,
        3 => config.interface.border_style,
        4 => config.interface.list_density,
        5 => config.interface.date_format,
        6 => if (config.display.show_images) "ON" else "OFF",
        7 => @tagName(config.display.image_protocol),
        8 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.list_width}),
        9 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.thread_width}),
        10 => try std.fmt.allocPrint(surface.frameAllocator(), "{d}", .{config.display.detail_width}),
        11 => config.collection.default_username orelse "(not set)",
        12 => try maskedToken(surface, config.apiClientToken()),
        13 => config_path orelse "(unknown)",
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

    try std.testing.expectEqual(@as(usize, 14), state.list.items.len);
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

test "settings exposes image protocol cycle row" {
    var state: State = .{};

    for (0..image_protocol_index) |_| state.updateList(.move_next);

    try std.testing.expectEqual(CycleField.image_protocol, state.focusedCycleField().?);
    try std.testing.expect(state.focusedEditField() == null);
}

test "settings exposes interface cycle rows" {
    var state: State = .{};

    try std.testing.expectEqual(CycleField.color_theme, state.focusedCycleField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(CycleField.transition, state.focusedCycleField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(CycleField.selection, state.focusedCycleField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(CycleField.border_style, state.focusedCycleField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(CycleField.list_density, state.focusedCycleField().?);
    state.updateList(.move_next);
    try std.testing.expectEqual(CycleField.date_format, state.focusedCycleField().?);
}

test "settings border style picker previews without mutating committed config" {
    var state: State = .{};
    var config: config_mod.Config = .{ .interface = .{ .border_style = "rounded" } };

    state.openPicker(.border_style, config, 10);

    try std.testing.expect(state.pickerOpen());
    try std.testing.expectEqual(@as(usize, 1), state.picker.?.committed_index);
    try std.testing.expectEqual(@as(usize, 1), state.picker.?.preview_index);
    try std.testing.expectEqualStrings("rounded", state.pickerSelectedValue().?);

    state.movePickerNext(11);

    try std.testing.expectEqualStrings("rounded", config.interface.border_style);
    try std.testing.expectEqualStrings("thick", state.pickerSelectedValue().?);
    try std.testing.expectEqualStrings("thick", state.previewConfig(config).interface.border_style);

    config.interface.border_style = "double";
    state.closePicker();
    try std.testing.expect(!state.pickerOpen());
    try std.testing.expectEqualStrings("double", state.previewConfig(config).interface.border_style);
}

test "settings visual pickers preview without mutating committed config" {
    var state: State = .{};
    const config: config_mod.Config = .{ .interface = .{
        .color_theme = "default",
        .transition = "none",
        .selection = "none",
        .border_style = "rounded",
        .list_density = "normal",
        .date_format = "yyyy-mm-dd",
    } };

    state.openPicker(.color_theme, config, 10);
    state.movePickerNext(11);
    try std.testing.expectEqualStrings("default", config.interface.color_theme);
    try std.testing.expectEqualStrings("blue", state.previewConfig(config).interface.color_theme);

    state.openPicker(.transition, config, 12);
    state.movePickerNext(13);
    try std.testing.expectEqualStrings("none", config.interface.transition);
    try std.testing.expectEqualStrings("none", state.previewConfig(config).interface.transition);

    state.openPicker(.selection, config, 15);
    state.movePickerNext(16);
    try std.testing.expectEqualStrings("none", config.interface.selection);
    try std.testing.expectEqualStrings("invert", state.previewConfig(config).interface.selection);

    state.openPicker(.list_density, config, 20);
    state.movePickerNext(21);
    try std.testing.expectEqualStrings("normal", config.interface.list_density);
    try std.testing.expectEqualStrings("comfortable", state.previewConfig(config).interface.list_density);

    state.openPicker(.date_format, config, 30);
    state.movePickerNext(31);
    try std.testing.expectEqualStrings("yyyy-mm-dd", config.interface.date_format);
    try std.testing.expectEqualStrings("yyyy/mm/dd", state.previewConfig(config).interface.date_format);
}

test "settings picker supports visual fields in current slice" {
    try std.testing.expect(pickerValues(.color_theme) != null);
    try std.testing.expect(pickerValues(.transition) != null);
    try std.testing.expect(pickerValues(.selection) != null);
    try std.testing.expect(pickerValues(.border_style) != null);
    try std.testing.expect(pickerValues(.list_density) != null);
    try std.testing.expect(pickerValues(.date_format) != null);
    try std.testing.expect(pickerValues(.image_protocol) == null);
}
