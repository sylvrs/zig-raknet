const std = @import("std");
const network = @import("network");
const Buffer = @import("buffer.zig").Buffer;
const message = @import("message.zig");

/// The magic bytes used to identify an offline message in RakNet
pub const RakNetMagic: [16]u8 = [_]u8{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };

pub const Server = struct {
    const MAX_MESSAGE_SIZE: usize = 65535;

    const ServerError = error{InvalidMagic};

    name: []const u8 = "Server",
    address: network.EndPoint,
    arena: std.heap.ArenaAllocator,
    socket: network.Socket = undefined,

    pub fn init(allocator: std.mem.Allocator, address: network.EndPoint) !Server {
        return .{
            .address = address,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    /// Deinitialize the arena used by the server
    pub fn deinit(self: *Server) void {
        self.arena.deinit();
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
            const decoded = self.decodeMessage(details.sender, raw[0..details.numberOfBytes]) catch |err| {
                std.debug.print("[{s}] Error while decoding packet from {s}: {any}\n", .{ self.name, details.sender, err });
                continue;
            };

            // just do a simple print for now
            switch (decoded) {
                .UnconnectedPing => {
                    std.debug.print("[{s}] Received UnconnectedPing from {s}: {any} \n", .{ self.name, details.sender, decoded });
                },
            }
        }
    }

    /// Decodes a raw packet into a message
    pub fn decodeMessage(self: *Server, sender: network.EndPoint, raw: []const u8) !message.OfflineMessage {
        std.debug.print("[{s}] Received packet from {s} of size {d} bytes\n", .{ self.name, sender, raw.len });

        // initialize buffer & reader
        var buffer = Buffer.init(raw);
        const reader = buffer.reader();

        // read pid & attempt to decode
        const pid = try reader.readByte();
        return try message.OfflineMessage.from(pid, reader);
    }
};
