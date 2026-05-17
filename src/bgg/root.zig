pub const client = @import("client.zig");
pub const endpoint = @import("endpoint.zig");
pub const err = @import("error.zig");
pub const html = @import("html.zig");
pub const model = @import("model.zig");
pub const xml = @import("xml.zig");

test {
    _ = client;
    _ = endpoint;
    _ = err;
    _ = html;
    _ = model;
    _ = xml;
}
