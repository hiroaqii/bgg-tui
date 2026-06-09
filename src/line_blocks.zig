const std = @import("std");
const ui = @import("chasen_ui");

/// Build one-row block metadata for the current line-based detail/thread renderers.
///
/// bgg-tui still flattens rich content into lines before drawing. This helper
/// keeps the temporary `BlockViewport` bridge in one place until those screens
/// move to semantic multi-row blocks.
pub fn oneRowBlocks(allocator: std.mem.Allocator, line_count: usize) ![]const ui.BlockViewport.Block {
    const blocks = try allocator.alloc(ui.BlockViewport.Block, line_count);
    @memset(blocks, .{ .height = 1 });
    return blocks;
}
