const std = @import("std");
const network = @import("network");
const helpers = @import("../utils/helpers.zig");
const raknet = @import("../raknet.zig");
const RakNetMagic = raknet.RakNetMagic;

pub const UnconnectedMessageIds = enum(u8) {
    UnconnectedPing = 0x01,
    UnconnectedPong = 0x1c,
    OpenConnectionRequest1 = 0x05,
    OpenConnectionReply1 = 0x06,
    OpenConnectionRequest2 = 0x07,
    OpenConnectionReply2 = 0x08,
    IncompatibleProtocolVersion = 0x19,
};

pub const UnconnectedMessage = union(UnconnectedMessageIds) {
    UnconnectedPing: struct { ping_time: i64, magic: @TypeOf(RakNetMagic), client_guid: i64 },
    UnconnectedPong: struct { pong_time: i64, server_guid: i64, magic: @TypeOf(RakNetMagic), server_pong_data: []const u8 },
    OpenConnectionRequest1: struct { magic: @TypeOf(RakNetMagic), protocol_version: u8, mtu_padding: []const u8 },
    OpenConnectionReply1: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, use_security: bool, mtu_size: i16 },
    OpenConnectionRequest2: struct { magic: @TypeOf(RakNetMagic), server_address: network.EndPoint, mtu_size: i16, client_guid: i64 },
    OpenConnectionReply2: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool },
    IncompatibleProtocolVersion: struct { protocol: u8, magic: @TypeOf(RakNetMagic), server_guid: i64 },

    /// Creates an UnconnectedPong struct given the current time, server GUID, and the server's pong data.
    pub fn createUnconnectedPong(pong_time: i64, server_guid: i64, server_pong_data: []const u8) UnconnectedMessage {
        return .{
            .UnconnectedPong = .{
                .pong_time = pong_time,
                .server_guid = server_guid,
                .magic = RakNetMagic,
                .server_pong_data = server_pong_data,
            },
        };
    }

    /// Creates an OpenConnectionReply1 struct given the server GUID, whether or not to use security, and the MTU size.
    pub fn createOpenConnectionReply1(server_guid: i64, use_security: bool, mtu_size: i16) UnconnectedMessage {
        return .{
            .OpenConnectionReply1 = .{
                .magic = RakNetMagic,
                .server_guid = server_guid,
                .use_security = use_security,
                .mtu_size = mtu_size,
            },
        };
    }

    /// Creates an OpenConnectionReply2 struct given the server GUID, client address, MTU size, and whether or not to use encryption.
    pub fn createOpenConnectionReply2(server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool) UnconnectedMessage {
        return .{
            .OpenConnectionReply2 = .{
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
            .UnconnectedPing => {
                const ping_time = try reader.readIntBig(i64);
                try helpers.verifyMagic(reader);
                const client_guid = try reader.readIntBig(i64);
                return .{ .UnconnectedPing = .{ .ping_time = ping_time, .magic = RakNetMagic, .client_guid = client_guid } };
            },
            .UnconnectedPong => {
                const pong_time = try reader.readIntBig(i64);
                const server_guid = try reader.readIntBig(i64);
                try helpers.verifyMagic(reader);
                const length = try reader.readIntBig(u16);
                // store the current index for slicing
                const start = try stream.getPos();
                try reader.skipBytes(length, .{});
                // slice the buffer from the start to the current index
                const pong_data = stream.buffer[start..try stream.getPos()];
                return .{
                    .UnconnectedPong = .{
                        .pong_time = pong_time,
                        .server_guid = server_guid,
                        .magic = RakNetMagic,
                        .server_pong_data = pong_data,
                    },
                };
            },
            .OpenConnectionRequest1 => {
                try helpers.verifyMagic(reader);
                const protocol_version = try reader.readByte();
                var mtu_padding = [_]u8{0} ** raknet.MaxMTUSize;
                const mtu_size = try reader.readAll(&mtu_padding);
                return .{
                    .OpenConnectionRequest1 = .{
                        .magic = RakNetMagic,
                        .protocol_version = protocol_version,
                        .mtu_padding = mtu_padding[0..mtu_size],
                    },
                };
            },
            .OpenConnectionRequest2 => {
                try helpers.verifyMagic(reader);
                const server_address = try helpers.readAddress(reader);
                const mtu_size = try reader.readIntBig(i16);
                const client_guid = try reader.readIntBig(i64);
                return .{
                    .OpenConnectionRequest2 = .{
                        .magic = RakNetMagic,
                        .server_address = server_address,
                        .mtu_size = mtu_size,
                        .client_guid = client_guid,
                    },
                };
            },
            else => error.UnsupportedMessageDecode,
        };
    }

    pub fn encode(self: UnconnectedMessage, writer: anytype) !void {
        try writer.writeByte(@intFromEnum(self));
        return switch (self) {
            .UnconnectedPing => |ping| {
                try writer.writeIntBig(i64, ping.ping_time);
                try writer.writeAll(RakNetMagic);
                try writer.writeIntBig(i64, ping.client_guid);
            },
            .UnconnectedPong => |pong| {
                try writer.writeIntBig(i64, pong.pong_time);
                try writer.writeIntBig(i64, pong.server_guid);
                try writer.writeAll(RakNetMagic);
                try helpers.writeString(writer, pong.server_pong_data);
            },
            .OpenConnectionReply1 => |reply1| {
                try writer.writeAll(RakNetMagic);
                try writer.writeIntBig(i64, reply1.server_guid);
                try writer.writeByte(@intFromBool(reply1.use_security));
                try writer.writeIntBig(i16, reply1.mtu_size);
            },
            .OpenConnectionReply2 => |reply2| {
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
            .UnconnectedPing => |msg| try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ msg.ping_time, msg.client_guid }),
            .UnconnectedPong => |msg| try writer.print(
                "UnconnectedPong {{ pong_time: {}, server_guid: {}, server_pong_data: {s} }}",
                .{ msg.pong_time, msg.server_guid, msg.server_pong_data },
            ),
            .OpenConnectionRequest1 => |msg| try writer.print(
                "OpenConnectionRequest1 {{ protocol_version: {}, mtu_size: {} }}",
                .{ msg.protocol_version, msg.mtu_padding.len },
            ),
            .OpenConnectionReply1 => |msg| try writer.print(
                "OptionConnectionReply1 {{ server_guid: {}, use_security: {}, mtu_size: {} }}",
                .{ msg.server_guid, msg.use_security, msg.mtu_size },
            ),
            .OpenConnectionRequest2 => |msg| try writer.print(
                "OpenConnectionRequest1 {{ server_address: {}, mtu_size: {}, client_guid: {} }}",
                .{ msg.server_address, msg.mtu_size, msg.client_guid },
            ),
            .OpenConnectionReply2 => |msg| try writer.print(
                "OptionConnectionReply1 {{ server_guid: {}, client_address: {}, mtu_size: {}, encryption_enabled: {} }}",
                .{ msg.server_guid, msg.client_address, msg.mtu_size, msg.encryption_enabled },
            ),
            .IncompatibleProtocolVersion => |msg| try writer.print(
                "IncompatibleProtocolVersion {{ protocol: {}, server_guid: {} }}",
                .{ msg.protocol, msg.server_guid },
            ),
        }
    }
};
