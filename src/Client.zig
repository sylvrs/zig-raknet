const std = @import("std");
const network = @import("network");
const raknet = @import("raknet.zig");
const Logger = @import("utils/Logger.zig");
const UnconnectedMessage = @import("message/unconnected.zig").UnconnectedMessage;

const Self = @This();

/// The allocator used for various client allocations
allocator: std.mem.Allocator,
logger: Logger,
/// The random GUID used to identify this client
guid: i64,
/// The socket that is used to send and receive packets
connected_socket: ?network.Socket = null,

/// The options used to configure the client
const ClientOptions = struct {
    allocator: std.mem.Allocator,
    guid: ?i64 = null,
    verbose: bool = false,
};

/// Initializes a new Client from the given options
pub fn init(options: ClientOptions) Self {
    return .{
        .allocator = options.allocator,
        .guid = options.guid orelse blk: {
            var prng = std.rand.DefaultPrng.init(inner: {
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
                break :inner seed;
            });
            const rand = prng.random();
            break :blk rand.int(i64);
        },
        .logger = .{ .verbose = options.verbose },
    };
}

pub fn deinit(_: *Self) void {}

/// Pings the specified address and returns the pong
pub fn ping(self: *Self, address: []const u8, port: u16, recv_buf: []u8) !UnconnectedMessage {
    const socket = try network.connectToHost(self.allocator, address, port, .udp);
    defer socket.close();
    try sendUnconnectedMessage(socket, UnconnectedMessage.createUnconnectedPing(
        std.time.milliTimestamp(),
        self.guid,
    ));
    const size = try socket.receive(recv_buf);
    return try UnconnectedMessage.from(recv_buf[0..size]);
}

/// Sends an unconnected message to the specified receiver
fn sendUnconnectedMessage(socket: network.Socket, msg: UnconnectedMessage) !void {
    var write_buffer = [_]u8{0} ** raknet.MaxMTUSize;
    var stream = std.io.fixedBufferStream(&write_buffer);
    const writer = stream.writer();
    try msg.encode(writer);
    _ = try socket.send(stream.getWritten());
}

test "ensure client properly receives message" {
    try init();
    defer deinit();

    var client = init(.{ .allocator = std.testing.allocator, .verbose = true });
    defer client.deinit();
    var recv_buf = [_]u8{0} ** raknet.MaxMTUSize;
    const msg = try client.ping("play.nethergames.org", 19132, &recv_buf);
    try std.testing.expect(msg == .unconnected_pong);
    try std.testing.expectStringStartsWith(msg.unconnected_pong.server_pong_data, "MCPE");
}
