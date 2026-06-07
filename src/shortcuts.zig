const chasen = @import("chasen");
const ui = @import("chasen_ui");

pub fn vimListMove(key: chasen.Key) ?ui.List.Msg {
    if (key.codepoint == 'k') return .move_prev;
    if (key.codepoint == 'j') return .move_next;
    return null;
}

pub fn vimMenuMove(key: chasen.Key) ?ui.Menu.Msg {
    if (key.codepoint == 'k') return .move_prev;
    if (key.codepoint == 'j') return .move_next;
    return null;
}
