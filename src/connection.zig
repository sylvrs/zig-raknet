const std = @import("std");
const network = @import("network");
const raknet = @import("raknet.zig");

const FrameBuilder = @import("message/frame.zig").FrameBuilder;
const DataMessage = @import("message/message.zig").DataMessage;
const ConnectedMessage = @import("message/connected.zig").ConnectedMessage;
const Logger = @import("utils/Logger.zig");

const DummySystemAddress = network.EndPoint{
    .address = .{ .ipv4 = network.Address.IPv4.init(127, 0, 0, 1) },
    .port = 0,
};

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
/// The logger used for the connection.
logger: Logger,
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
    verbose: bool = false,
}) Self {
    return Self{
        .address = options.address,
        .server = options.server,
        .mtu_size = options.mtu_size,
        .client_guid = options.client_guid,
        .allocator = options.allocator,
        .pending_messages = std.AutoHashMap(u16, FrameBuilder).init(options.allocator),
        .logger = .{ .verbose = options.verbose },
    };
}

/// Handles a message received from the client.
pub fn handleMessage(self: *Self, received: DataMessage) !void {
    self.logger.info("[Connection: {}]: Received message: {}", .{ self.address, received });
    switch (received) {
        .ack => {},
        .nack => {},
        .datagram => |msg| {
            for (msg.frames.items) |frame| {
                if (frame.fragment()) |fragment| {
                    self.logger.info("[Connection: {}]: Received fragment: {}", .{ self.address, fragment });
                } else {
                    const connected_msg = ConnectedMessage.from(frame.body()) catch |err| {
                        self.logger.err("[Connection: {}]: Failed to parse connected message: {}", .{ self.address, err });
                        return;
                    };
                    self.handleConnectedMessage(connected_msg) catch |err| {
                        self.logger.err("[Connection: {}]: Failed to handle connected message: {}", .{ self.address, err });
                    };
                }
            }
        },
    }
}

/// Handles a connected message received from the client.
fn handleConnectedMessage(self: *Self, msg: ConnectedMessage) !void {
    switch (msg) {
        .connection_request => |request| {
            self.logger.info("[Connection: {}] Received connection request", .{self.address});
            const internal_ids = [_]network.EndPoint{DummySystemAddress} ** raknet.RakNetSystemAddressCount;
            self.sendMessage(.{
                .connection_request_accepted = .{
                    .client_address = self.address,
                    .internal_ids = &internal_ids,
                    .send_ping_time = request.send_ping_time,
                    .send_pong_time = std.time.milliTimestamp(),
                },
            }) catch |err| {
                self.logger.err("[Connection: {}]: Failed to send connection request accepted: {}", .{ self.address, err });
            };
            self.state = .connecting;
        },
        .connected_ping => {
            self.logger.info("[Connection: {}]: Received connected ping", .{self.address});
        },
        .disconnection_notification => {
            self.state = .disconnected;
            self.logger.info("[Connection: {}]: Disconnected", .{self.address});
            _ = self.server.connections.remove(self.address);
        },
        else => self.logger.warn("[Connection: {}]: Received unknown connected message: {s}", .{ self.address, @tagName(msg) }),
    }
}

/// Sends a message to the client.
pub fn sendMessage(self: *Self, msg: ConnectedMessage) !void {
    if (self.state == .disconnected) {
        self.logger.warn("[Connection: {}]: Attempted to send message to disconnected client", .{self.address});
        return;
    }
    var write_buffer = [_]u8{0} ** raknet.MaxMTUSize;
    var stream = std.io.fixedBufferStream(&write_buffer);
    const writer = stream.writer();
    try msg.encode(writer);
    _ = try self.server.socket.sendTo(self.address, stream.getWritten());
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
