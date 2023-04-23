const std = @import("std");
const raknet = @import("raknet");
const network = @import("network");

pub fn main() !void {
    // create a server
    var server = try raknet.Server.init(
        std.heap.page_allocator,
        .{
            .address = .{ .ipv4 = try network.Address.IPv4.parse("127.0.0.1") },
            .port = 19132,
        },
    );
    defer server.deinit();
    std.debug.print("Listening to data on {any}\n", .{server.address});
    try server.start();
}
