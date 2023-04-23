const std = @import("std");
const RakNetMagic = @import("raknet.zig").RakNetMagic;

pub const OfflineMessageIds = enum {
    UnconnectedPing,
    UnconnectedPong,

    pub fn fromByte(value: u8) !OfflineMessageIds {
        return switch (value) {
            0x01 => .UnconnectedPing,
            0x1c => .UnconnectedPong,
            else => error.InvalidOfflineMessageId,
        };
    }

    pub fn toByte(self: OfflineMessageIds) u8 {
        return switch (self) {
            .UnconnectedPing => 0x01,
            .UnconnectedPong => 0x1c,
        };
    }
};

pub const OfflineMessage = union(OfflineMessageIds) {
    UnconnectedPing: struct {
        ping_time: i64,
        client_guid: i64,
    },
    UnconnectedPong: struct {
        pong_time: i64,
        server_guid: i64,
        magic: [16]u8,
        server_name: []const u8,
    },

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

    /// Attempts to construct an OfflineMessage from a packet ID & reader.
    pub fn from(pid: u8, reader: anytype) !OfflineMessage {
        const message_id = try OfflineMessageIds.fromByte(pid);
        return switch (message_id) {
            .UnconnectedPing => {
                const ping_time = try reader.readIntBig(i64);
                const received_magic = try reader.readBoundedBytes(RakNetMagic.len);
                if (!std.mem.eql(u8, &RakNetMagic, received_magic.buffer[0..received_magic.len])) {
                    return error.InvalidMagic;
                }
                const client_guid = try reader.readIntBig(i64);
                return .{
                    .UnconnectedPing = .{
                        .ping_time = ping_time,
                        .client_guid = client_guid,
                    },
                };
            },
            else => error.UnsupportedOfflineMessageId,
        };
    }

    pub fn encode(self: OfflineMessage, writer: anytype) !void {
        switch (self) {
            .UnconnectedPong => {
                try writer.writeByte(OfflineMessageIds.UnconnectedPong.toByte());
                try writer.writeIntBig(i64, self.UnconnectedPong.pong_time);
                try writer.writeIntBig(i64, self.UnconnectedPong.server_guid);
                try writer.writeAll(&RakNetMagic);
                try writer.writeIntBig(u16, @intCast(u16, self.UnconnectedPong.server_name.len));
                try writer.writeAll(self.UnconnectedPong.server_name);
            },
            else => error.UnsupportedOfflineMessageId,
        }
    }

    /// Custom formatter for OfflineMessage.
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .UnconnectedPing => try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ value.UnconnectedPing.ping_time, value.UnconnectedPing.client_guid }),
            .UnconnectedPong => try writer.print("UnconnectedPong {{ pong_time: {}, server_guid: {}, server_name: {s} }}", .{ value.UnconnectedPong.pong_time, value.UnconnectedPong.server_guid, value.UnconnectedPong.server_name }),
        }
    }
};
