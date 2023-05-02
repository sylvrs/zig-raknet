const std = @import("std");
const raknet = @import("raknet.zig");
const RakNetMagic = raknet.RakNetMagic;
const helpers = @import("helpers.zig");
const network = @import("network");

pub const OfflineMessageIds = enum(u8) {
    UnconnectedPing = 0x01,
    UnconnectedPong = 0x1c,
    OpenConnectionRequest1 = 0x05,
    OpenConnectionReply1 = 0x06,
    OpenConnectionRequest2 = 0x07,
    OpenConnectionReply2 = 0x08,
    IncompatibleProtocolVersion = 0x19,
};

pub const OfflineMessage = union(OfflineMessageIds) {
    UnconnectedPing: struct { ping_time: i64, client_guid: i64 },
    UnconnectedPong: struct { pong_time: i64, server_guid: i64, magic: @TypeOf(RakNetMagic), server_name: []const u8 },
    OpenConnectionRequest1: struct { magic: @TypeOf(RakNetMagic), protocol_version: u8, mtu_padding: []const u8 },
    OpenConnectionReply1: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, use_security: bool, mtu_size: i16 },
    OpenConnectionRequest2: struct { magic: @TypeOf(RakNetMagic), server_address: network.EndPoint, mtu_size: i16, client_guid: i64 },
    OpenConnectionReply2: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool },
    IncompatibleProtocolVersion: struct { protocol: u8, magic: @TypeOf(RakNetMagic), server_guid: i64 },

    /// Creates an UnconnectedPong struct given the current time, server GUID, and server name.
    pub fn createUnconnectedPong(pong_time: i64, server_guid: i64, server_name: []const u8) OfflineMessage {
        return .{
            .UnconnectedPong = .{
                .pong_time = pong_time,
                .server_guid = server_guid,
                .magic = RakNetMagic,
                .server_name = server_name,
            },
        };
    }

    /// Creates an OpenConnectionReply1 struct given the server GUID, whether or not to use security, and the MTU size.
    pub fn createOpenConnectionReply1(server_guid: i64, use_security: bool, mtu_size: i16) OfflineMessage {
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
    pub fn createOpenConnectionReply2(server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool) OfflineMessage {
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
    pub fn from(pid: u8, reader: anytype) !OfflineMessage {
        return switch (try std.meta.intToEnum(OfflineMessageIds, pid)) {
            .UnconnectedPing => {
                const ping_time = try reader.readIntBig(i64);
                try helpers.verifyMagic(reader);
                const client_guid = try reader.readIntBig(i64);
                return .{
                    .UnconnectedPing = .{
                        .ping_time = ping_time,
                        .client_guid = client_guid,
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
            else => error.UnsupportedOfflineMessageId,
        };
    }

    pub fn encode(self: OfflineMessage, writer: anytype) !void {
        return switch (self) {
            .UnconnectedPong => {
                try writer.writeByte(@enumToInt(self));
                try writer.writeIntBig(i64, self.UnconnectedPong.pong_time);
                try writer.writeIntBig(i64, self.UnconnectedPong.server_guid);
                try writer.writeAll(&RakNetMagic);
                try helpers.writeString(writer, self.UnconnectedPong.server_name);
            },
            .OpenConnectionReply1 => {
                try writer.writeByte(@enumToInt(self));
                try writer.writeAll(&RakNetMagic);
                try writer.writeIntBig(i64, self.OpenConnectionReply1.server_guid);
                try writer.writeByte(@boolToInt(self.OpenConnectionReply1.use_security));
                try writer.writeIntBig(i16, self.OpenConnectionReply1.mtu_size);
            },
            .OpenConnectionReply2 => {
                try writer.writeByte(@enumToInt(self));
                try writer.writeAll(&RakNetMagic);
                try writer.writeIntBig(i64, self.OpenConnectionReply2.server_guid);
                try helpers.writeAddress(writer, self.OpenConnectionReply2.client_address);
                try writer.writeIntBig(i16, self.OpenConnectionReply2.mtu_size);
                try writer.writeByte(@boolToInt(self.OpenConnectionReply2.encryption_enabled));
            },
            else => error.UnsupportedOfflineMessageId,
        };
    }

    /// Custom formatter for OfflineMessage.
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .UnconnectedPing => try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ value.UnconnectedPing.ping_time, value.UnconnectedPing.client_guid }),
            .UnconnectedPong => try writer.print("UnconnectedPong {{ pong_time: {}, server_guid: {}, server_name: {s} }}", .{ value.UnconnectedPong.pong_time, value.UnconnectedPong.server_guid, value.UnconnectedPong.server_name }),
            .OpenConnectionRequest1 => try writer.print("OpenConnectionRequest1 {{ protocol_version: {}, mtu_size: {} }}", .{ value.OpenConnectionRequest1.protocol_version, value.OpenConnectionRequest1.mtu_padding.len }),
            .OpenConnectionReply1 => try writer.print("OpenConnectionReply1 {{ server_guid: {}, use_security: {}, mtu_size: {} }}", .{ value.OpenConnectionReply1.server_guid, value.OpenConnectionReply1.use_security, value.OpenConnectionReply1.mtu_size }),
            .OpenConnectionRequest2 => try writer.print("OpenConnectionRequest2 {{ server_address: {}, mtu_size: {}, client_guid: {} }}", .{ value.OpenConnectionRequest2.server_address, value.OpenConnectionRequest2.mtu_size, value.OpenConnectionRequest2.client_guid }),
            .OpenConnectionReply2 => try writer.print("OpenConnectionReply2 {{ server_guid: {}, client_address: {}, mtu_size: {}, encryption_enabled: {} }}", .{ value.OpenConnectionReply2.server_guid, value.OpenConnectionReply2.client_address, value.OpenConnectionReply2.mtu_size, value.OpenConnectionReply2.encryption_enabled }),
            .IncompatibleProtocolVersion => try writer.print("IncompatibleProtocolVersion {{ protocol: {}, server_guid: {} }}", .{ value.IncompatibleProtocolVersion.protocol, value.IncompatibleProtocolVersion.server_guid }),
        }
    }
};

pub const OnlineMessageIds = enum(u8) {
    ConnectedPing = 0x00,
    ConnectedPong = 0x03,
    ConnectionRequest = 0x09,
    ConnectionRequestAccepted = 0x10,
    NewIncomingConnection = 0x13,
    DisconnectionNotification = 0x15,
    Ack = 0xc0,
    Nack = 0xa0,
    UserPacket = 0x86,
};

pub const OnlineMessage = union(OnlineMessageIds) {
    ConnectedPing: struct { ping_time: i64 },
    ConnectedPong: struct { ping_time: i64, pong_time: i64 },
    ConnectionRequest: struct { client_guid: i64, time: i64 },
    ConnectionRequestAccepted: struct { client_address: network.EndPoint, system_index: i16, internal_ids: []network.EndPoint, request_time: i64, time: i64 },
    NewIncomingConnection: struct { address: network.EndPoint, internal_address: network.EndPoint },
    DisconnectionNotification: struct {},
    Ack: struct {},
    Nack: struct {},
    UserPacket: struct {},

    /// Attempts to construct an OfflineMessage from a packet ID & reader.
    pub fn from(reader: anytype) !OnlineMessage {
        const pid = try reader.readByte();
        return switch (pid) {
            @enumToInt(OnlineMessageIds.Ack) => .{ .Ack = .{} },
            @enumToInt(OnlineMessageIds.Nack) => .{ .Nack = .{} },
            else => error.UnsupportedOnlineMessageId,
        };
    }

    /// Custom parser for OnlineMessage
    pub fn format(_: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, _: anytype) !void {}
};
