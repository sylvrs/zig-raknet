const std = @import("std");

test {
    _ = @import("helpers.zig");
    _ = @import("message.zig");
    _ = @import("raknet.zig");
    std.testing.refAllDecls(@This());
}
