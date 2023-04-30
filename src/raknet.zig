const std = @import("std");
const network = @import("network");
const message = @import("message.zig");

/// The magic bytes used to identify an offline message in RakNet
pub const RakNetMagic: [16]u8 = [_]u8{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };

pub const Server = struct {
    const LoggedPrefix = "Server";
    const MAX_MESSAGE_SIZE: usize = 65535;

    const ServerError = error{InvalidMagic};
    name: []const u8,
    guid: i64,
    address: network.EndPoint,
    socket: network.Socket = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, guid: i64, address: network.EndPoint) !Server {
        return .{
            .name = name,
            .guid = guid,
            .address = address,
            .allocator = allocator,
        };
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
        try self.receiveLoop();
    }

    /// The main loop for receiving and processing packets
    pub fn receiveLoop(self: *Server) !void {
        var raw = [_]u8{0} ** MAX_MESSAGE_SIZE;
        while (true) {
            const details = try self.socket.receiveFrom(raw[0..]);
            // attempt to decode the message (or skip it if it's invalid)
            const decoded = decodeMessage(raw[0..details.numberOfBytes]) catch |err| {
                std.debug.print("[{s}] Error while decoding packet from {s}: {any}\n", .{ LoggedPrefix, details.sender, err });
                continue;
            };

            // just do a simple print for now
            switch (decoded) {
                .UnconnectedPing => {
                    const response = message.OfflineMessage.createUnconnectedPong(decoded.UnconnectedPing.ping_time, self.guid, self.name);
                    var write_buffer = [_]u8{0} ** MAX_MESSAGE_SIZE;
                    var stream = std.io.fixedBufferStream(&write_buffer);
                    var writer = stream.writer();
                    try response.encode(writer);
                    _ = try self.socket.sendTo(details.sender, stream.getWritten());
                },
                else => std.debug.print("[{s}] Received unknown packet from {s} of size {d} bytes\n", .{ LoggedPrefix, details.sender, raw.len }),
            }
        }
    }

    /// Decodes a raw packet into a message
    fn decodeMessage(raw: []const u8) !message.OfflineMessage {
        // initialize buffer & reader
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();

        // read pid & attempt to decode
        const pid = try reader.readByte();
        return try message.OfflineMessage.from(pid, reader);
    }
};
