const std = @import("std");
const network = @import("network");
const raknet = @import("raknet");

pub fn main() !void {
    // initialize networking (required for Windows)
    try raknet.init();
    defer raknet.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var client = raknet.Client.init(.{ .allocator = gpa.allocator(), .verbose = true });
    defer client.deinit();
    for (0..5) |_| {
        var recv_buf: [1024]u8 = undefined;
        const msg = try client.ping("play.nethergames.org", 19132, &recv_buf);
        std.debug.print("Received message: {}\n", .{msg});
        // sleep for two seconds
        std.time.sleep(std.time.ns_per_s * 2);
    }
}
