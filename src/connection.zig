const std = @import("std");
const network = @import("network");

const FrameBuilder = @import("message/frame.zig").FrameBuilder;
const DataMessage = @import("message/message.zig").DataMessage;
const ConnectedMessage = @import("message/connected.zig").ConnectedMessage;
const raknet = @import("raknet.zig");

const Self = @This();

pub const State = enum { initializing, connecting, connected, disconnected };
/// The address of the client.
address: network.EndPoint,
/// A pointer to the server that this connection is associated with.
server: *raknet.Server,
/// The maximum transmission unit size of the connection.
mtu_size: i16,
/// The client's unique identifier.
client_guid: i64,
/// The allocator used when handling internals for the connection.
allocator: std.mem.Allocator,
// Pending messages that need to be finished before handling.
pending_messages: std.AutoHashMap(u16, FrameBuilder),
/// The latency of the connection.
latency: u64 = 0,
/// The state of the connection.
state: State = .initializing,

/// Initializes a new connection.
pub fn init(options: struct {
    allocator: std.mem.Allocator,
    address: network.EndPoint,
    server: *raknet.Server,
    mtu_size: i16,
    client_guid: i64,
}) Self {
    return Self{
        .address = options.address,
        .server = options.server,
        .mtu_size = options.mtu_size,
        .client_guid = options.client_guid,
        .allocator = options.allocator,
        .pending_messages = std.AutoHashMap(u16, FrameBuilder).init(options.allocator),
    };
}

/// Handles a message received from the client.
pub fn handleMessage(self: *Self, received: DataMessage) !void {
    self.server.logger.info("[Connection: {}]: Received message: {}", .{ self.address, received });
    switch (received) {
        .ack => {},
        .nack => {},
        .datagram => |msg| {
            for (msg.frames.items) |frame| {
                _ = frame;
            }
        },
    }
}

/// Sends a message to the client.
pub fn sendMessage(self: *Self, msg: ConnectedMessage) !void {
    if (self.state == .disconnected) {
        self.server.logger.warn("[Connection: {}]: Attempted to send message to disconnected client", .{self.address});
        return;
    }
    self.server.sendMessage(self.address, msg);
}

/// Custom formatting for the connection.
pub fn format(value: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Connection {{ address: {}, mtu_size: {}, client_guid: {}, latency: {}, state: {} }}", .{
        value.address,
        value.mtu_size,
        value.client_guid,
        value.latency,
        value.state,
    });
}
