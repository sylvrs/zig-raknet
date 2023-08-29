const std = @import("std");
const frame = @import("frame.zig");

pub const UnconnectedMessage = @import("unconnected.zig").UnconnectedMessage;
pub const ConnectedMessage = @import("connected.zig").ConnectedMessage;

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

    /// Custom parser for DataMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .Ack => try writer.print("Ack {{ }}", .{}),
            .Nack => try writer.print("Nack {{ }}", .{}),
            .Datagram => try writer.print("Datagram {{ flags: {}, sequence_number: {}, frame_count: {} }}", .{ value.Datagram.flags, value.Datagram.sequence_number, value.Datagram.frames.len }),
        }
    }

    /// Attempts to construct an DataMessage from a packet ID & reader.
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
