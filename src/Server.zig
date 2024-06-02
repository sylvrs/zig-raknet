const std = @import("std");
const network = @import("network");
const raknet = @import("raknet.zig");
const Connection = @import("connection.zig");
const Logger = @import("utils/Logger.zig");

const UnconnectedMessage = @import("message/unconnected.zig").UnconnectedMessage;
const DataMessage = @import("message/message.zig").DataMessage;
const ConnectedMessage = @import("message/connected.zig").ConnectedMessage;

const Self = @This();

/// The data that is sent in an unconnected pong
pong_data: []const u8,
/// The random GUID used to identify this server
guid: i64,
/// The address used to listen for incoming connections
endpoint: network.EndPoint,
/// The connections that are currently active
connections: std.AutoHashMap(network.EndPoint, Connection),
/// The allocator used for various tasks in the server
allocator: std.mem.Allocator,
/// The logger used to print messages
logger: Logger,
/// Whether or not the server is running
running: bool = true,
/// The socket that is created when the server is started
socket: network.Socket = undefined,

/// The options used to initialize a new Server
const ServerOptions = struct {
    allocator: std.mem.Allocator,
    pong_data: ?[]const u8 = null,
    guid: ?i64 = null,
    endpoint: network.EndPoint,
    verbose: bool = false,
};

/// Initializes a new Server from the given options
pub fn init(options: ServerOptions) Self {
    return .{
        .pong_data = if (options.pong_data) |pong_data| pong_data else "",
        // generate a random guid if none was provided
        .guid = options.guid orelse blk: {
            var prng = std.rand.DefaultPrng.init(inner: {
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;
                break :inner seed;
            });
            break :blk prng.random().int(i64);
        },
        .endpoint = options.endpoint,
        .connections = std.AutoHashMap(network.EndPoint, Connection).init(options.allocator),
        .allocator = options.allocator,
        .logger = .{ .verbose = options.verbose },
    };
}

/// Sets the data that is sent in an unconnected pong
pub fn setPongData(self: *Self, data: []const u8) void {
    self.pong_data = data;
}

/// Start server and listen for incoming connections
pub fn accept(self: *Self) !void {
    // create UDP socket on IPv4
    self.socket = try network.Socket.create(.ipv4, .udp);
    defer self.socket.close();
    // configure socket
    try self.socket.setBroadcast(true);
    // start listening
    try self.socket.bind(self.endpoint);
    // start accepting connections
    self.logger.info("Listening on {any}", .{self.endpoint});
    while (self.running) {
        self.receive() catch |err| {
            self.logger.err("Error while receiving packet: {any}", .{err});
        };
    }
}

/// The main loop for receiving and processing packets
pub fn receive(self: *Self) !void {
    var buffer = [_]u8{0} ** raknet.MaxMTUSize;
    const details = try self.socket.receiveFrom(&buffer);
    const raw = buffer[0..details.numberOfBytes];
    var associated_connection = self.connections.get(details.sender);
    // if we don't have a connection, attempt to handle it as an offline message
    if (associated_connection) |*found_connection| {
        const msg = DataMessage.from(self.allocator, raw) catch |err| {
            self.logger.err("Error while decoding datagram message (0x{x:0>2}) from {s}: {any}", .{ raw[0], details.sender, err });
            return;
        };
        try found_connection.handleMessage(msg);
    } else {
        // attempt to decode the message (or skip it if it's invalid)
        const msg = UnconnectedMessage.from(raw) catch return;
        try self.handleUnconnectedMessage(details.sender, msg);
    }
}

/// Handles a decoded, unconnected message
fn handleUnconnectedMessage(self: *Self, sender: network.EndPoint, received_message: UnconnectedMessage) !void {
    switch (received_message) {
        .unconnected_ping => |msg| {
            // send pong back
            try self.sendUnconnectedMessage(
                sender,
                UnconnectedMessage.createUnconnectedPong(
                    msg.ping_time,
                    self.guid,
                    self.pong_data,
                ),
            );
        },
        .open_connection_request1 => |msg| {
            self.logger.info("Received OpenConnectionRequest1 from {s}: {any}", .{ sender, received_message });
            if (msg.protocol_version != raknet.RakNetProtocolVersion) {
                self.logger.warn("Received OpenConnectionRequest1 with invalid protocol version from {s}", .{sender});
                try self.sendUnconnectedMessage(sender, UnconnectedMessage.createIncompatibleProtocolVersion(raknet.RakNetProtocolVersion, self.guid));
                return;
            }
            try self.sendUnconnectedMessage(
                sender,
                UnconnectedMessage.createOpenConnectionReply1(
                    self.guid,
                    false,
                    @intCast(received_message.open_connection_request1.mtu_padding.len),
                ),
            );
        },
        .open_connection_request2 => |msg| {
            self.logger.info("Received OpenConnectionRequest2 from {s}: {any}", .{ sender, received_message });
            try self.sendUnconnectedMessage(
                sender,
                UnconnectedMessage.createOpenConnectionReply2(
                    self.guid,
                    sender,
                    received_message.open_connection_request2.mtu_size,
                    false,
                ),
            );
            // create connection
            const new_connection = Connection.init(.{
                .allocator = self.allocator,
                .address = sender,
                .server = self,
                .mtu_size = msg.mtu_size,
                .client_guid = msg.client_guid,
            });
            try self.connections.put(sender, new_connection);
            self.logger.info("Created new connection for {s}", .{sender});
        },
        else => self.logger.warn("Received unknown packet from {s}", .{sender}),
    }
}

/// Sends an unconnected message to the specified receiver
pub fn sendUnconnectedMessage(self: *Self, receiver: network.EndPoint, msg: UnconnectedMessage) !void {
    var write_buffer = [_]u8{0} ** raknet.MaxMTUSize;
    var stream = std.io.fixedBufferStream(&write_buffer);
    const writer = stream.writer();
    try msg.encode(writer);
    _ = try self.socket.sendTo(receiver, stream.getWritten());
}
