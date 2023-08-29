const std = @import("std");
const network = @import("network");
const DataMessage = @import("message/message.zig").DataMessage;
const raknet = @import("raknet.zig");

const Self = @This();

pub const State = enum {
    Initializing,
    Connecting,
    Connected,
    Disconnected,
};

address: network.EndPoint,
server: *raknet.Server,
mtu_size: i16,
client_guid: i64,
latency: u64 = 0,
state: State = .Initializing,

pub fn handleMessage(self: *Self, msg: DataMessage) !void {
    self.server.logger.info("[Connection: {}]: Received message: {}", .{ self.address, msg });
}

pub fn sendMessage(self: *Self, msg: []const u8) !void {
    _ = msg;
    _ = self;
}

pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try writer.print("Connection {{ address: {}, mtu_size: {}, client_guid: {}, latency: {}, state: {} }}", .{
        value.address,
        value.mtu_size,
        value.client_guid,
        value.latency,
        value.state,
    });
}
