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
                return .{ .UnconnectedPing = .{ .ping_time = ping_time, .client_guid = client_guid } };
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
        try writer.writeByte(@intFromEnum(self));
        return switch (self) {
            .UnconnectedPong => |pong| {
                try writer.writeIntBig(i64, pong.pong_time);
                try writer.writeIntBig(i64, pong.server_guid);
                try writer.writeAll(RakNetMagic);
                try helpers.writeString(writer, pong.server_name);
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
            else => error.UnsupportedOfflineMessageId,
        };
    }

    /// Custom formatter for OfflineMessage.
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // we could use comptime here w/ @tagName but this is more concise
        switch (value) {
            .UnconnectedPing => |msg| try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ msg.ping_time, msg.client_guid }),
            .UnconnectedPong => |msg| try writer.print(
                "UnconnectedPong {{ pong_time: {}, server_guid: {}, server_name: {s} }}",
                .{ msg.pong_time, msg.server_guid, msg.server_name },
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
        }
    }
};

/// Data messages are the outermost packet layer of connections.
/// Each datagram must have the Datagram flag set.
/// The Ack and Nack flags are mutually exclusive.
pub const DataMessageFlags = enum(u8) {
    Datagram = 0x80,
    Ack = 0x40,
    Nack = 0x20,

    /// Returns the flags as a byte.
    pub fn ordinal(self: DataMessageFlags) u8 {
        return @intFromEnum(self);
    }
};
pub const DataMessage = union(enum) {
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
    pub fn from(allocator: std.mem.Allocator, raw: []const u8) !DataMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        const pid = try reader.readByte();
        // if bitwise-and gives us 0, then it's not a valid Datagram
        if (pid & DataMessageFlags.Datagram.ordinal() == 0) {
            return error.InvalidOnlineMessageId;
        }

        if (pid & DataMessageFlags.Ack.ordinal() != 0) {
            return .{ .Ack = .{} };
        } else if (pid & DataMessageFlags.Nack.ordinal() != 0) {
            return .{ .Nack = .{} };
        } else {
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
        }
    }
};

/// Connected messages are the inner layer of the Datagram type of the DataMessage.
pub const ConnectedMessageIds = enum(u8) {
    ConnectedPing = 0x00,
    ConnectedPong = 0x03,
    ConnectionRequest = 0x09,
    ConnectionRequestAccepted = 0x10,
    NewIncomingConnection = 0x13,
    DisconnectionNotification = 0x15,
    UserMessage = 0x86,
};

pub const ConnectedMessage = union(ConnectedMessageIds) {
    ConnectedPing: struct { ping_time: i64 },
    ConnectedPong: struct { ping_time: i64, pong_time: i64 },
    ConnectionRequest: struct { client_guid: i64, time: i64 },
    ConnectionRequestAccepted: struct { client_address: network.EndPoint, system_index: i16, internal_ids: []network.EndPoint, request_time: i64, time: i64 },
    NewIncomingConnection: struct { address: network.EndPoint, internal_address: network.EndPoint },
    DisconnectionNotification: struct {},
    UserMessage: struct { id: u32, buffer: []const u8 },

    /// Attempts to construct an ConnectedMessage from a packet ID & reader.
    pub fn from(raw: []const u8) !ConnectedMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        return switch (try std.meta.intToEnum(ConnectedMessageIds, try reader.readByte())) {
            .ConnectedPing => @panic("ConnectedPing is not implemented"),
            .ConnectedPong => @panic("ConnectedPong is not implemented"),
            .ConnectionRequest => @panic("ConnectionRequest is not implemented"),
            .ConnectionRequestAccepted => @panic("ConnectionRequestAccepted is not implemented"),
            .NewIncomingConnection => @panic("NewIncomingConnection is not implemented"),
            .DisconnectionNotification => .{ .DisconnectionNotification = .{} },
            .UserMessage => @panic("UserMessage is not implemented"),
        };
    }

    /// Custom parser for OnlineMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // we could use comptime here w/ @tagName but this is more concise
        switch (value) {
            .ConnectedPing => |msg| try writer.print("ConnectedPing {{ ping_time: {} }}", .{msg.ping_time}),
            .ConnectedPong => |msg| try writer.print("ConnectedPong {{ ping_time: {}, pong_time: {} }}", .{ msg.ping_time, msg.pong_time }),
            .ConnectionRequest => |msg| try writer.print("ConnectionRequest {{ client_guid: {}, time: {} }}", .{ msg.client_guid, msg.time }),
            .ConnectionRequestAccepted => |msg| try writer.print(
                "ConnectionRequestAccepted {{ client_address: {}, system_index: {}, internal_ids: {any}, request_time: {}, time: {} }}",
                .{ msg.client_address, msg.system_index, msg.internal_ids, msg.request_time, msg.time },
            ),
            .NewIncomingConnection => |msg| try writer.print(
                "NewIncomingConnection {{ address: {any}, internal_address: {any} }}",
                .{ msg.address, msg.internal_address },
            ),
            .DisconnectionNotification => try writer.print("DisconnectionNotification {{ }}", .{}),
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
