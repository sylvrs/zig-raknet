const std = @import("std");
const network = @import("network");
const message = @import("message.zig");
const connection = @import("connection.zig");

/// The magic bytes used to identify an offline message in RakNet
pub const RakNetMagic: [16]u8 = [_]u8{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };
/// The types of errors that can occur while processing a RakNet message
pub const RakNetError = error{InvalidMagic};
/// The current version of the RakNet protocol
pub const RakNetProtocolVersion = 11;
/// The maximum size of a packet that can be sent at a time
pub const MaxMTUSize = 1500;

pub const Server = struct {
    const MAX_MESSAGE_SIZE: usize = 65535;
    name: []const u8,
    guid: i64,
    address: network.EndPoint,
    connections: std.AutoHashMap(network.EndPoint, connection.Connection),
    allocator: std.mem.Allocator,
    running: bool = true,
    verbose: bool = false,
    socket: network.Socket = undefined,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, guid: i64, address: network.EndPoint) !Server {
        return .{
            .name = name,
            .guid = guid,
            .address = address,
            .connections = std.AutoHashMap(network.EndPoint, connection.Connection).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn logErr(self: *Server, comptime format: []const u8, args: anytype) void {
        if (self.verbose) {
            std.log.err(format, args);
        }
    }

    pub fn logInfo(self: *Server, comptime format: []const u8, args: anytype) void {
        if (self.verbose) {
            std.log.info(format, args);
        }
    }

    pub fn logWarn(self: *Server, comptime format: []const u8, args: anytype) void {
        if (self.verbose) {
            std.log.warn(format, args);
        }
    }

    pub fn logDebug(self: *Server, comptime format: []const u8, args: anytype) void {
        if (self.verbose) {
            std.log.debug(format, args);
        }
    }

    /// Start server and listen for incoming connections
    pub fn start(self: *Server) !void {
        // create UDP socket on IPv4
        self.socket = try network.Socket.create(.ipv4, .udp);
        defer self.socket.close();
        // configure socket
        try self.socket.setBroadcast(true);
        // start listening
        try self.socket.bind(self.address);
        // start accepting connections
        self.logInfo("Listening on {any}", .{self.address});
        while (self.running) {
            self.receive() catch |err| {
                self.logErr("Error while receiving packet: {any}", .{err});
            };
        }
    }

    /// The main loop for receiving and processing packets
    pub fn receive(self: *Server) !void {
        var buffer = [_]u8{0} ** MaxMTUSize;
        const details = try self.socket.receiveFrom(buffer[0..]);
        const raw = buffer[0..details.numberOfBytes];
        var associated_connection = self.connections.get(details.sender);
        // if we don't have a connection, attempt to handle it as an offline message
        if (associated_connection) |*found_connection| {
            const msg = message.DataMessage.from(self.allocator, raw) catch |err| {
                self.logErr("Error while decoding datagram message (0x{x:0>2}) from {s}: {any}", .{ raw[0], details.sender, err });
                return;
            };
            try found_connection.handleMessage(msg);
        } else {
            // attempt to decode the message (or skip it if it's invalid)
            const msg = message.UnconnectedMessage.from(raw) catch |err| {
                self.logErr("Error while decoding offline message (0x{x:0>2}) from {s}: {any}", .{ raw[0], details.sender, err });
                return;
            };
            try self.handleUnconnectedMessage(details.sender, msg);
        }
    }

    /// Handles a decoded, unconnected message
    fn handleUnconnectedMessage(self: *Server, sender: network.EndPoint, received_message: message.UnconnectedMessage) !void {
        switch (received_message) {
            .UnconnectedPing => {
                // send pong back
                try self.sendUnconnectedMessage(
                    sender,
                    message.UnconnectedMessage.createUnconnectedPong(
                        received_message.UnconnectedPing.ping_time,
                        self.guid,
                        self.name,
                    ),
                );
            },
            .OpenConnectionRequest1 => {
                self.logInfo("Received OpenConnectionRequest1 from {s}: {any}", .{ sender, received_message });
                try self.sendUnconnectedMessage(
                    sender,
                    message.UnconnectedMessage.createOpenConnectionReply1(
                        self.guid,
                        false,
                        @intCast(i16, received_message.OpenConnectionRequest1.mtu_padding.len),
                    ),
                );
            },
            .OpenConnectionRequest2 => {
                self.logInfo("Received OpenConnectionRequest2 from {s}: {any}", .{ sender, received_message });
                try self.sendUnconnectedMessage(
                    sender,
                    message.UnconnectedMessage.createOpenConnectionReply2(
                        self.guid,
                        sender,
                        received_message.OpenConnectionRequest2.mtu_size,
                        false,
                    ),
                );
                // create connection
                var new_connection = connection.Connection{
                    .address = sender,
                    .server = self,
                    .mtu_size = received_message.OpenConnectionRequest2.mtu_size,
                    .client_guid = received_message.OpenConnectionRequest2.client_guid,
                };
                try self.connections.put(sender, new_connection);
                self.logInfo("Created new connection for {s}", .{sender});
            },
            else => self.logWarn("Received unknown packet from {s}", .{sender}),
        }
    }

    pub fn sendUnconnectedMessage(self: *Server, receiver: network.EndPoint, msg: message.UnconnectedMessage) !void {
        var write_buffer = [_]u8{0} ** MAX_MESSAGE_SIZE;
        var stream = std.io.fixedBufferStream(&write_buffer);
        var writer = stream.writer();
        try msg.encode(writer);
        _ = try self.socket.sendTo(receiver, stream.getWritten());
    }
};
