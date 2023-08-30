const std = @import("std");
const network = @import("network");
const helpers = @import("../utils/helpers.zig");
const raknet = @import("../raknet.zig");
const RakNetMagic = raknet.RakNetMagic;

pub const UnconnectedMessageIds = enum(u8) {
    unconnected_ping = 0x01,
    unconnected_pong = 0x1c,
    open_connection_request1 = 0x05,
    open_connection_reply1 = 0x06,
    open_connection_request2 = 0x07,
    open_connection_reply2 = 0x08,
    incompatible_protocol_version = 0x19,
};

pub const UnconnectedMessage = union(UnconnectedMessageIds) {
    unconnected_ping: struct { ping_time: i64, magic: @TypeOf(RakNetMagic), client_guid: i64 },
    unconnected_pong: struct { pong_time: i64, server_guid: i64, magic: @TypeOf(RakNetMagic), server_pong_data: []const u8 },
    open_connection_request1: struct { magic: @TypeOf(RakNetMagic), protocol_version: u8, mtu_padding: []const u8 },
    open_connection_reply1: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, use_security: bool, mtu_size: i16 },
    open_connection_request2: struct { magic: @TypeOf(RakNetMagic), server_address: network.EndPoint, mtu_size: i16, client_guid: i64 },
    open_connection_reply2: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool },
    incompatible_protocol_version: struct { protocol: u8, magic: @TypeOf(RakNetMagic), server_guid: i64 },

    /// Creates an Unconnected Ping packet given the current time and client GUID.
    pub fn createUnconnectedPing(ping_time: i64, client_guid: i64) UnconnectedMessage {
        return .{ .unconnected_ping = .{ .ping_time = ping_time, .magic = RakNetMagic, .client_guid = client_guid } };
    }

    /// Creates an Unconnected Pong packet given the current time, server GUID, and the server's pong data.
    pub fn createUnconnectedPong(pong_time: i64, server_guid: i64, server_pong_data: []const u8) UnconnectedMessage {
        return .{
            .unconnected_pong = .{
                .pong_time = pong_time,
                .server_guid = server_guid,
                .magic = RakNetMagic,
                .server_pong_data = server_pong_data,
            },
        };
    }

    /// Creates an Open Connection Request 1 packet given the protocol version and MTU padding.
    pub fn createOpenConnectionRequest1(protocol_version: u8, mtu_padding: []const u8) UnconnectedMessage {
        return .{
            .open_connection_request1 = .{
                .magic = RakNetMagic,
                .protocol_version = protocol_version,
                .mtu_padding = mtu_padding,
            },
        };
    }

    /// Creates an Open Connection Reply 1 packet given the server GUID, whether or not to use security, and the MTU size.
    pub fn createOpenConnectionReply1(server_guid: i64, use_security: bool, mtu_size: i16) UnconnectedMessage {
        return .{
            .open_connection_reply1 = .{
                .magic = RakNetMagic,
                .server_guid = server_guid,
                .use_security = use_security,
                .mtu_size = mtu_size,
            },
        };
    }

    /// Creates an Open Connection Request 2 packet given the server address, MTU size, and client GUID.
    pub fn createOpenConnectionRequest2(server_address: network.EndPoint, mtu_size: i16, client_guid: i64) UnconnectedMessage {
        return .{
            .open_connection_request2 = .{
                .magic = RakNetMagic,
                .server_address = server_address,
                .mtu_size = mtu_size,
                .client_guid = client_guid,
            },
        };
    }

    /// Creates an Open Connection Reply 2 packet given the server GUID, client address, MTU size, and whether or not to use encryption.
    pub fn createOpenConnectionReply2(server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool) UnconnectedMessage {
        return .{
            .open_connection_reply2 = .{
                .magic = RakNetMagic,
                .server_guid = server_guid,
                .client_address = client_address,
                .mtu_size = mtu_size,
                .encryption_enabled = encryption_enabled,
            },
        };
    }

    /// Attempts to construct an OfflineMessage from a packet ID & reader.
    pub fn from(raw: []const u8) !UnconnectedMessage {
        // initialize buffer & reader
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();

        // read pid & attempt to decode
        const pid = try reader.readByte();
        return switch (try std.meta.intToEnum(UnconnectedMessageIds, pid)) {
            .unconnected_ping => {
                const ping_time = try reader.readIntBig(i64);
                try helpers.verifyMagic(reader);
                const client_guid = try reader.readIntBig(i64);
                return createUnconnectedPing(ping_time, client_guid);
            },
            .unconnected_pong => {
                const pong_time = try reader.readIntBig(i64);
                const server_guid = try reader.readIntBig(i64);
                try helpers.verifyMagic(reader);
                const length = try reader.readIntBig(u16);
                // store the current index for slicing
                const start = try stream.getPos();
                try reader.skipBytes(length, .{});
                // slice the buffer from the start to the current index
                const pong_data = stream.buffer[start..try stream.getPos()];
                return createUnconnectedPong(pong_time, server_guid, pong_data);
            },
            .open_connection_request1 => {
                try helpers.verifyMagic(reader);
                const protocol_version = try reader.readByte();
                const start = try stream.getPos();
                // read the rest of the buffer (up to the max MTU size) as MTU padding
                var mtu_padding = [_]u8{0} ** raknet.MaxMTUSize;
                _ = try reader.readAll(&mtu_padding);
                const end = try stream.getPos();
                if (end != try stream.getEndPos()) {
                    return error.BytesLeftInBuffer;
                }
                return createOpenConnectionRequest1(protocol_version, stream.buffer[start..end]);
            },
            .open_connection_request2 => {
                try helpers.verifyMagic(reader);
                const server_address = try helpers.readAddress(reader);
                const mtu_size = try reader.readIntBig(i16);
                const client_guid = try reader.readIntBig(i64);
                return createOpenConnectionRequest2(server_address, mtu_size, client_guid);
            },
            else => error.UnsupportedMessageDecode,
        };
    }

    pub fn encode(self: UnconnectedMessage, writer: anytype) !void {
        try writer.writeByte(@intFromEnum(self));
        return switch (self) {
            .unconnected_ping => |ping| {
                try writer.writeIntBig(i64, ping.ping_time);
                try writer.writeAll(RakNetMagic);
                try writer.writeIntBig(i64, ping.client_guid);
            },
            .unconnected_pong => |pong| {
                try writer.writeIntBig(i64, pong.pong_time);
                try writer.writeIntBig(i64, pong.server_guid);
                try writer.writeAll(RakNetMagic);
                try helpers.writeString(writer, pong.server_pong_data);
            },
            .open_connection_reply1 => |reply1| {
                try writer.writeAll(RakNetMagic);
                try writer.writeIntBig(i64, reply1.server_guid);
                try writer.writeByte(@intFromBool(reply1.use_security));
                try writer.writeIntBig(i16, reply1.mtu_size);
            },
            .open_connection_reply2 => |reply2| {
                try writer.writeAll(RakNetMagic);
                try writer.writeIntBig(i64, reply2.server_guid);
                try helpers.writeAddress(writer, reply2.client_address);
                try writer.writeIntBig(i16, reply2.mtu_size);
                try writer.writeByte(@intFromBool(reply2.encryption_enabled));
            },
            else => error.UnsupportedMessageEncode,
        };
    }

    /// Custom formatter for OfflineMessage.
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // we could use comptime here w/ @tagName but this is more concise
        switch (value) {
            .unconnected_ping => |msg| try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ msg.ping_time, msg.client_guid }),
            .unconnected_pong => |msg| try writer.print(
                "UnconnectedPong {{ pong_time: {}, server_guid: {}, server_pong_data: {s} }}",
                .{ msg.pong_time, msg.server_guid, msg.server_pong_data },
            ),
            .open_connection_request1 => |msg| try writer.print(
                "OpenConnectionRequest1 {{ protocol_version: {}, mtu_size: {} }}",
                .{ msg.protocol_version, msg.mtu_padding.len },
            ),
            .open_connection_reply1 => |msg| try writer.print(
                "OpenConnectionReply1 {{ server_guid: {}, use_security: {}, mtu_size: {} }}",
                .{ msg.server_guid, msg.use_security, msg.mtu_size },
            ),
            .open_connection_request2 => |msg| try writer.print(
                "OpenConnectionRequest2 {{ server_address: {}, mtu_size: {}, client_guid: {} }}",
                .{ msg.server_address, msg.mtu_size, msg.client_guid },
            ),
            .open_connection_reply2 => |msg| try writer.print(
                "OpenConnectionReply2 {{ server_guid: {}, client_address: {}, mtu_size: {}, encryption_enabled: {} }}",
                .{ msg.server_guid, msg.client_address, msg.mtu_size, msg.encryption_enabled },
            ),
            .incompatible_protocol_version => |msg| try writer.print(
                "IncompatibleProtocolVersion {{ protocol: {}, server_guid: {} }}",
                .{ msg.protocol, msg.server_guid },
            ),
        }
    }
};
