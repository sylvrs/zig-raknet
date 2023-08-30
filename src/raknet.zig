const std = @import("std");
const network = @import("network");
const message = @import("message/message.zig");
const DataMessage = message.DataMessage;
const UnconnectedMessage = message.UnconnectedMessage;
const Connection = @import("Connection.zig");
const Logger = @import("utils/Logger.zig");

/// The magic bytes used to identify an offline message in RakNet
pub const RakNetMagic: []const u8 = &.{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };
/// The types of errors that can occur while processing a RakNet message
pub const RakNetError = error{InvalidMagic};
/// The current version of the RakNet protocol
pub const RakNetProtocolVersion = 11;
/// The maximum size of a packet that can be sent at a time
pub const MaxMTUSize = 1500;

pub const Server = struct {
    /// The data that is sent in an unconnected pong
    pong_data: []const u8,
    /// The random GUID used to identify this server
    guid: i64,
    /// The address used to listen for incoming connections
    endpoint: network.EndPoint,
    /// The connections that are currently active
    connections: std.AutoHashMap(network.EndPoint, Connection),
    allocator: std.mem.Allocator,
    /// The logger used to print messages
    logger: Logger,
    /// Whether or not the server is running
    running: bool = true,
    /// The socket that is created when the server is started
    socket: network.Socket = undefined,

    /// Initializes a new Server from the given options
    pub fn init(options: struct {
        allocator: std.mem.Allocator,
        pong_data: ?[]const u8 = null,
        guid: ?i64 = null,
        endpoint: network.EndPoint,
        verbose: bool = false,
    }) Server {
        return .{
            .pong_data = if (options.pong_data) |pong_data| pong_data else "",
            // generate a random guid if none was provided
            .guid = options.guid orelse blk: {
                var prng = std.rand.DefaultPrng.init(inner: {
                    var seed: u64 = undefined;
                    std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
                    break :inner seed;
                });
                const rand = prng.random();
                break :blk rand.int(i64);
            },
            .endpoint = options.endpoint,
            .connections = std.AutoHashMap(network.EndPoint, Connection).init(options.allocator),
            .allocator = options.allocator,
            .logger = .{ .verbose = options.verbose },
        };
    }

    /// Sets the data that is sent in an unconnected pong
    pub fn setPongData(self: *Server, data: []const u8) void {
        self.pong_data = data;
    }

    /// Start server and listen for incoming connections
    pub fn accept(self: *Server) !void {
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
    pub fn receive(self: *Server) !void {
        var buffer = [_]u8{0} ** MaxMTUSize;
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
            const msg = UnconnectedMessage.from(raw) catch |err| {
                self.logger.err("Error while decoding offline message (0x{x:0>2}) from {s}: {any}", .{ raw[0], details.sender, err });
                return;
            };
            try self.handleUnconnectedMessage(details.sender, msg);
        }
    }

    /// Handles a decoded, unconnected message
    fn handleUnconnectedMessage(self: *Server, sender: network.EndPoint, received_message: UnconnectedMessage) !void {
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
            .open_connection_request1 => {
                self.logger.info("Received open_connection_request1 from {s}: {any}", .{ sender, received_message });
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
                self.logger.info("Received open_connection_request2 from {s}: {any}", .{ sender, received_message });
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
                var new_connection = Connection{
                    .address = sender,
                    .server = self,
                    .mtu_size = msg.mtu_size,
                    .client_guid = msg.client_guid,
                };
                try self.connections.put(sender, new_connection);
                self.logger.info("Created new connection for {s}", .{sender});
            },
            else => self.logger.warn("Received unknown packet from {s}", .{sender}),
        }
    }

    /// Sends an unconnected message to the specified receiver
    pub fn sendUnconnectedMessage(self: *Server, receiver: network.EndPoint, msg: UnconnectedMessage) !void {
        var write_buffer = [_]u8{0} ** MaxMTUSize;
        var stream = std.io.fixedBufferStream(&write_buffer);
        var writer = stream.writer();
        try msg.encode(writer);
        _ = try self.socket.sendTo(receiver, stream.getWritten());
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    logger: Logger,
    /// The random GUID used to identify this client
    guid: i64,
    /// The socket that is used to send and receive packets
    connected_socket: ?network.Socket = null,

    /// Initializes a new Client from the given options
    pub fn init(options: struct { allocator: std.mem.Allocator, guid: ?i64 = null, verbose: bool = false }) Client {
        // ensure the network is initialized if we're on Windows
        network.init() catch unreachable;
        return .{
            .allocator = options.allocator,
            .guid = options.guid orelse blk: {
                var prng = std.rand.DefaultPrng.init(inner: {
                    var seed: u64 = undefined;
                    std.os.getrandom(std.mem.asBytes(&seed)) catch unreachable;
                    break :inner seed;
                });
                const rand = prng.random();
                break :blk rand.int(i64);
            },
            .logger = .{ .verbose = options.verbose },
        };
    }

    pub fn deinit(_: *Client) void {
        network.deinit();
    }

    /// Pings the specified address and returns the pong
    pub fn ping(self: *Client, address: []const u8, port: u16, recv_buf: []u8) !UnconnectedMessage {
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
        var write_buffer = [_]u8{0} ** MaxMTUSize;
        var stream = std.io.fixedBufferStream(&write_buffer);
        var writer = stream.writer();
        try msg.encode(writer);
        _ = try socket.sendTo(socket.endpoint orelse return error.UnknownEndpoint, stream.getWritten());
    }
};

test "ensure client properly receives message" {
    var client = Client.init(.{ .allocator = std.testing.allocator, .verbose = true });
    defer client.deinit();
    var recv_buf = [_]u8{0} ** MaxMTUSize;
    const msg = try client.ping("play.nethergames.org", 19132, &recv_buf);
    try std.testing.expect(msg == .unconnected_pong);
    try std.testing.expectStringStartsWith(msg.unconnected_pong.server_pong_data, "MCPE");
}
