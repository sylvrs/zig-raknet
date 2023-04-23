const std = @import("std");
const RakNetMagic = @import("raknet.zig").RakNetMagic;

pub const OfflineMessageIds = enum {
    UnconnectedPing,

    pub fn fromByte(value: u8) !OfflineMessageIds {
        return switch (value) {
            0x01 => .UnconnectedPing,
            else => error.InvalidOfflineMessageId,
        };
    }
};

pub const OfflineMessage = union(OfflineMessageIds) {
    UnconnectedPing: struct {
        ping_time: i64,
        client_guid: i64,
    },

    /// Attempts to construct an OfflineMessage from a packet ID & reader.
    pub fn from(pid: u8, reader: anytype) !OfflineMessage {
        const message_id = try OfflineMessageIds.fromByte(pid);
        switch (message_id) {
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
        }
    }

    /// Custom formatter for OfflineMessage.
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .UnconnectedPing => try writer.print("UnconnectedPing {{ ping_time: {}, client_guid: {} }}", .{ value.UnconnectedPing.ping_time, value.UnconnectedPing.client_guid }),
        }
    }
};
