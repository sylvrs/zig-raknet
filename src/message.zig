const std = @import("std");
const network = @import("network");
const raknet = @import("raknet.zig");
const RakNetMagic = raknet.RakNetMagic;
const helpers = @import("helpers.zig");
const frame = @import("frame.zig");

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
    UnconnectedPing: struct { ping_time: i64, client_guid: i64 },
    UnconnectedPong: struct { pong_time: i64, server_guid: i64, magic: @TypeOf(RakNetMagic), server_name: []const u8 },
    OpenConnectionRequest1: struct { magic: @TypeOf(RakNetMagic), protocol_version: u8, mtu_padding: []const u8 },
    OpenConnectionReply1: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, use_security: bool, mtu_size: i16 },
    OpenConnectionRequest2: struct { magic: @TypeOf(RakNetMagic), server_address: network.EndPoint, mtu_size: i16, client_guid: i64 },
    OpenConnectionReply2: struct { magic: @TypeOf(RakNetMagic), server_guid: i64, client_address: network.EndPoint, mtu_size: i16, encryption_enabled: bool },
    IncompatibleProtocolVersion: struct { protocol: u8, magic: @TypeOf(RakNetMagic), server_guid: i64 },

    /// Creates an UnconnectedPong struct given the current time, server GUID, and server name.
    pub fn createUnconnectedPong(pong_time: i64, server_guid: i64, server_name: []const u8) UnconnectedMessage {
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

    pub fn encode(self: UnconnectedMessage, writer: anytype) !void {
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

/// Connected messages are the outermost packet layer of connections.
pub const ConnectedMessageIds = enum(u8) { Ack = 0xc0, Nack = 0xa0, Datagram = 0x80 };
pub const ConnectedMessage = union(ConnectedMessageIds) {
    Ack: struct {},
    Nack: struct {},
    Datagram: struct { flags: u8, sequence_number: u24, frames: []frame.Frame },

    /// Custom parser for ConnectedMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .Ack => try writer.print("Ack {{ }}", .{}),
            .Nack => try writer.print("Nack {{ }}", .{}),
            .Datagram => try writer.print("Datagram {{ flags: {}, sequence_number: {}, frame_count: {} }}", .{ value.Datagram.flags, value.Datagram.sequence_number, value.Datagram.frames.len }),
        }
    }

    /// Attempts to construct an ConnectedMessage from a packet ID & reader.
    pub fn from(allocator: std.mem.Allocator, raw: []const u8) !ConnectedMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        const pid = try reader.readByte();
        return switch (pid) {
            @enumToInt(ConnectedMessageIds.Ack) => .{ .Ack = .{} },
            @enumToInt(ConnectedMessageIds.Nack) => .{ .Nack = .{} },
            else => {
                // received a non-datagram message while connected
                if (pid & @enumToInt(ConnectedMessageIds.Datagram) == 0) {
                    return error.InvalidOnlineMessageId;
                }
                // reset to the beginning of the packet
                stream.reset();

                const flags = try reader.readByte();
                const sequence_number = try reader.readIntLittle(u24);
                // we do not need to call deinit here because `toOwnedSlice` handles it for us
                var frames = std.ArrayList(frame.Frame).init(allocator);
                while (try stream.getPos() < try stream.getEndPos()) {
                    try frames.append(try frame.Frame.from(reader, allocator));
                }
                // todo: deallocate frames after use
                return .{ .Datagram = .{ .flags = flags, .sequence_number = sequence_number, .frames = try frames.toOwnedSlice() } };
            },
        };
    }
};

/// Datagram messages are the inner layer of the Datagram.
pub const DatagramMessageIds = enum(u8) {
    ConnectedPing = 0x00,
    ConnectedPong = 0x03,
    ConnectionRequest = 0x09,
    ConnectionRequestAccepted = 0x10,
    NewIncomingConnection = 0x13,
    DisconnectionNotification = 0x15,
    UserMessage = 0x86,
};

pub const DatagramMessage = union(DatagramMessageIds) {
    ConnectedPing: struct { ping_time: i64 },
    ConnectedPong: struct { ping_time: i64, pong_time: i64 },
    ConnectionRequest: struct { client_guid: i64, time: i64 },
    ConnectionRequestAccepted: struct { client_address: network.EndPoint, system_index: i16, internal_ids: []network.EndPoint, request_time: i64, time: i64 },
    NewIncomingConnection: struct { address: network.EndPoint, internal_address: network.EndPoint },
    DisconnectionNotification: struct {},
    UserMessage: struct { id: u32, buffer: []const u8 },

    /// Attempts to construct an ConnectedMessage from a packet ID & reader.
    pub fn from(raw: []const u8) !DatagramMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        const message_id = try std.meta.intToEnum(DatagramMessageIds, try reader.readByte());
        return switch (message_id) {
            .ConnectedPing => @compileError("ConnectedPing is not implemented"),
            .ConnectedPong => @compileError("ConnectedPong is not implemented"),
            .ConnectionRequest => @compileError("ConnectionRequest is not implemented"),
            .ConnectionRequestAccepted => @compileError("ConnectionRequestAccepted is not implemented"),
            .NewIncomingConnection => @compileError("NewIncomingConnection is not implemented"),
            .DisconnectionNotification => .{ .DisconnectionNotification = .{} },
            .UserMessage => @compileError("UserMessage is not implemented"),
        };
    }

    /// Custom parser for OnlineMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .ConnectedPing => try writer.print("ConnectedPing {{ ping_time: {} }}", .{value.ConnectedPing.ping_time}),
            .ConnectedPong => try writer.print("ConnectedPong {{ ping_time: {}, pong_time: {} }}", .{ value.ConnectedPong.ping_time, value.ConnectedPong.pong_time }),
            .ConnectionRequest => try writer.print("ConnectionRequest {{ client_guid: {}, time: {} }}", .{ value.ConnectionRequest.client_guid, value.ConnectionRequest.time }),
            .ConnectionRequestAccepted => try writer.print("ConnectionRequestAccepted {{ client_address: {}, system_index: {}, internal_ids: {any}, request_time: {}, time: {} }}", .{ value.ConnectionRequestAccepted.client_address, value.ConnectionRequestAccepted.system_index, value.ConnectionRequestAccepted.internal_ids, value.ConnectionRequestAccepted.request_time, value.ConnectionRequestAccepted.time }),
            .NewIncomingConnection => try writer.print("NewIncomingConnection {{ address: {any}, internal_address: {any} }}", .{ value.NewIncomingConnection.address, value.NewIncomingConnection.internal_address }),
            .DisconnectionNotification => try writer.print("DisconnectionNotification {{ }}", .{}),
            .Ack => try writer.print("Ack {{ }}", .{}),
            .Nack => try writer.print("Nack {{ }}", .{}),
            .Datagram => try writer.print("Datagram {{ flags: {}, sequence_number: {}, frame_count: {} }}", .{ value.Datagram.flags, value.Datagram.sequence_number, value.Datagram.frames.len }),
        }
    }
};

pub const MessageBuilder = struct {
    count: u32,
    allocator: std.mem.Allocator,
    pending_frames: std.AutoHashMap(u32, []const u8),

    pub fn init(count: u32, allocator: std.mem.Allocator) !MessageBuilder {
        return .{
            .count = count,
            .allocator = allocator,
            .pending_frames = std.AutoHashMap(u32, []const u8).init(allocator),
        };
    }

    pub fn add(self: *MessageBuilder, current_frame: frame.Frame) !void {
        if (try current_frame.fragment()) |fragment| {
            try self.pending_frames.put(
                fragment.fragment_id,
                try current_frame.body(),
            );
        } else {
            return error.InvalidFragment;
        }
    }

    pub fn complete(self: *MessageBuilder) bool {
        return self.pending_frames.count() == self.count;
    }

    pub fn build(self: *MessageBuilder) ![]const u8 {
        if (!self.complete()) {
            return error.IncompleteMessage;
        }
        var list = std.ArrayList(u8).init(self.allocator);
        var iterator = self.pending_frames.valueIterator();
        while (iterator.next()) |value| {
            try list.appendSlice(value.*);
        }
        defer {
            var destruction_iterator = self.pending_frames.valueIterator();
            while (destruction_iterator.next()) |value| {
                self.allocator.free(value.*);
            }
            self.pending_frames.deinit();
        }
        return try list.toOwnedSlice();
    }
};

test "test message builder allocation" {}
