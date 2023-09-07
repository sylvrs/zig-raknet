const std = @import("std");
const network = @import("network");
const frame = @import("frame.zig");

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
            .ConnectedPing => .{ .ConnectedPing = .{ .ping_time = try reader.readIntBig(i64) } },
            .ConnectedPong => .{
                .ConnectedPong = .{ .ping_time = try reader.readIntBig(i64), .pong_time = try reader.readIntBig(i64) },
            },
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
