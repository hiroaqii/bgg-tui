const selection = @import("motion/selection.zig");
const transition = @import("motion/transition.zig");

pub const selectionNeedsFrame = selection.selectionNeedsFrame;
pub const focusedStyle = selection.focusedStyle;
pub const drawFocusedText = selection.drawFocusedText;
pub const drawStatusScanText = selection.drawStatusScanText;

pub const applyScreenTransition = transition.applyScreenTransition;
