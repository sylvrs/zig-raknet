const std = @import("std");
const network = @import("network");
const message = @import("message/message.zig");
const DataMessage = message.DataMessage;
const UnconnectedMessage = message.UnconnectedMessage;
const ConnectedMessage = message.ConnectedMessage;
const Connection = @import("Connection.zig");
const Logger = @import("utils/Logger.zig");

/// The magic bytes used to identify an offline message in RakNet
pub const RakNetMagic: []const u8 = &.{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };
/// The types of errors that can occur while processing a RakNet message
pub const RakNetError = error{InvalidMagic};
/// The current version of the RakNet protocol
pub const RakNetProtocolVersion = 11;
/// How many addresses to send in a ConnectionRequestAccepted packet
pub const RakNetSystemAddressCount = 20;
/// The maximum size of a packet that can be sent at a time
pub const MaxMTUSize = 1500;

pub const Server = @import("Server.zig");
pub const Client = @import("Client.zig");

/// A wrapper function for zig-network's initialization (only needed on Windows)
pub fn init() !void {
    try network.init();
}

/// A wrapper function for zig-network's deinitialization (only needed on Windows)
pub fn deinit() void {
    network.deinit();
}
