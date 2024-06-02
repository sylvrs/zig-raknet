const std = @import("std");
const network = @import("network");
const helpers = @import("../utils/helpers.zig");
const frame = @import("frame.zig");

/// Connected messages are the inner layer of the Datagram type of the DataMessage.
pub const ConnectedMessageIds = enum(u8) {
    connected_ping = 0x00,
    connected_pong = 0x03,
    connection_request = 0x09,
    connection_request_accepted = 0x10,
    new_incoming_connection = 0x13,
    disconnection_notification = 0x15,
    user_message = 0x86,
};

pub const ConnectedMessage = union(ConnectedMessageIds) {
    connected_ping: struct { ping_time: i64 },
    connected_pong: struct { ping_time: i64, pong_time: i64 },
    connection_request: struct { client_guid: i64, send_ping_time: i64, use_security: bool },
    connection_request_accepted: struct { client_address: network.EndPoint, internal_ids: []const network.EndPoint, send_ping_time: i64, send_pong_time: i64 },
    new_incoming_connection: struct { address: network.EndPoint, internal_address: network.EndPoint },
    disconnection_notification: struct {},
    user_message: struct { id: u32, buffer: []const u8 },

    /// Attempts to construct an ConnectedMessage from a packet ID & reader.
    pub fn from(raw: []const u8) !ConnectedMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        return switch (try std.meta.intToEnum(ConnectedMessageIds, try reader.readByte())) {
            .connected_ping => .{ .connected_ping = .{ .ping_time = try reader.readInt(i64, .big) } },
            .connected_pong => .{
                .connected_pong = .{ .ping_time = try reader.readInt(i64, .big), .pong_time = try reader.readInt(i64, .big) },
            },
            .connection_request => .{ .connection_request = .{
                .client_guid = try reader.readInt(i64, .big),
                .send_ping_time = try reader.readInt(i64, .big),
                .use_security = try reader.readByte() == 1,
            } },
            // .connection_request_accepted => @panic("ConnectionRequestAccepted is not implemented"),
            // .new_incoming_connection => @panic("NewIncomingConnection is not implemented"),
            .disconnection_notification => .{ .disconnection_notification = .{} },
            // .user_message => @panic("UserMessage is not implemented"),
            else => error.UnknownConnectedMessageId,
        };
    }

    pub fn encode(self: ConnectedMessage, writer: anytype) !void {
        try writer.writeByte(@intFromEnum(self));
        return switch (self) {
            .connection_request => |msg| {
                try writer.writeInt(i64, msg.client_guid, .big);
                try writer.writeInt(i64, msg.send_ping_time, .big);
                try writer.writeByte(if (msg.use_security) 1 else 0);
            },
            .connection_request_accepted => |msg| {
                try helpers.writeAddress(writer, msg.client_address);
                try writer.writeInt(i16, @intCast(0), .big);
                for (msg.internal_ids) |address| {
                    try helpers.writeAddress(writer, address);
                }
                try writer.writeInt(i64, msg.send_ping_time, .big);
                try writer.writeInt(i64, msg.send_pong_time, .big);
            },
            else => error.UnknownConnectedMessageId,
        };
    }

    /// Custom parser for OnlineMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // we could use comptime here w/ @tagName but this is more concise
        switch (value) {
            .connected_ping => |msg| try writer.print("ConnectedPing {{ ping_time: {} }}", .{msg.ping_time}),
            .connected_pong => |msg| try writer.print("ConnectedPong {{ ping_time: {}, pong_time: {} }}", .{ msg.ping_time, msg.pong_time }),
            .connection_request => |msg| try writer.print("ConnectionRequest {{ client_guid: {}, time: {} }}", .{ msg.client_guid, msg.time }),
            .connection_request_accepted => |msg| try writer.print(
                "ConnectionRequestAccepted {{ client_address: {}, system_index: {}, internal_ids: {any}, request_time: {}, time: {} }}",
                .{ msg.client_address, msg.system_index, msg.internal_ids, msg.request_time, msg.time },
            ),
            .new_incoming_connection => |msg| try writer.print(
                "NewIncomingConnection {{ address: {any}, internal_address: {any} }}",
                .{ msg.address, msg.internal_address },
            ),
            .disconnection_notification => try writer.print("DisconnectionNotification {{ }}", .{}),
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
