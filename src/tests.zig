const std = @import("std");
pub const helpers = @import("utils/helpers.zig");
pub const message = @import("message/message.zig");
pub const connected = @import("message/connected.zig");
pub const frame = @import("message/frame.zig");
pub const unconnected_ping = @import("message/unconnected.zig");
pub const raknet = @import("raknet.zig");

// `refAllDecls(@This())` will search for any tests in the declarations (e.g., the `@import`s above) and attempt to run them.
// The declarations must be marked as `pub` for the function to be able to access them.
test {
    std.testing.refAllDecls(@This());
}
