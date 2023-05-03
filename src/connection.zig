const std = @import("std");
const network = @import("network");
const message = @import("message.zig");
const raknet = @import("raknet.zig");

pub const ConnectionState = enum {
    Initializing,
    Connecting,
    Connected,
    Disconnected,
};

pub const Connection = struct {
    address: network.EndPoint,
    server: *raknet.Server,
    mtu_size: i16,
    client_guid: i64,
    latency: u64 = 0,
    state: ConnectionState = .Initializing,

    pub fn handleMessage(self: *Connection, msg: message.DataMessage) !void {
        self.server.logInfo("[connection: {}]: Received message: {}", .{ self.address, msg });
    }

    pub fn sendMessage(self: *Connection, msg: []const u8) !void {
        _ = msg;
        _ = self;
    }

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Connection {{ address: {}, mtu_size: {}, client_guid: {}, latency: {}, state: {} }}", .{ value.address, value.mtu_size, value.client_guid, value.latency, value.state });
    }
};
