const std = @import("std");
pub const Frame = @import("frame.zig").Frame;
pub const AcknowledgeList = @import("AcknowledgeList.zig");
pub const UnconnectedMessage = @import("unconnected.zig").UnconnectedMessage;
pub const ConnectedMessage = @import("connected.zig").ConnectedMessage;

/// Data messages are the outermost packet layer of connections.
/// Each datagram must have the Datagram flag set.
/// The Ack and Nack flags are mutually exclusive.
pub const DataMessageFlags = enum(u8) {
    ack = 0x40,
    nack = 0x20,
    datagram = 0x80,

    /// Resolves the header flags to an enum.
    pub inline fn from(header_flags: u8) !DataMessageFlags {
        // not a valid data message header
        if (header_flags & DataMessageFlags.datagram.ordinal() == 0) {
            return error.InvalidHeaderFlags;
        }
        if (header_flags & DataMessageFlags.ack.ordinal() != 0) {
            return .ack;
        } else if (header_flags & DataMessageFlags.nack.ordinal() != 0) {
            return .nack;
        } else {
            return .datagram;
        }
    }

    /// Returns the flags as a byte.
    pub fn ordinal(self: DataMessageFlags) u8 {
        return @intFromEnum(self);
    }
};

pub const DataMessage = union(DataMessageFlags) {
    ack: AcknowledgeList,
    nack: AcknowledgeList,
    datagram: struct { flags: u8, sequence_number: u24, frames: std.ArrayList(Frame) },

    /// Custom parser for DataMessage
    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (value) {
            .ack => try writer.print("Ack {{ }}", .{}),
            .nack => try writer.print("Nack {{ }}", .{}),
            .datagram => |msg| try writer.print("Datagram {{ flags: {}, sequence_number: {}, frame_count: {} }}", .{ msg.flags, msg.sequence_number, msg.frames.items.len }),
        }
    }

    /// Attempts to construct an DataMessage from a packet ID & reader.
    /// The datagram's frames must be deallocated by the caller.
    pub fn from(allocator: std.mem.Allocator, raw: []const u8) !DataMessage {
        var stream = std.io.fixedBufferStream(raw);
        const reader = stream.reader();
        const header_flags = try reader.readByte();
        return switch (try DataMessageFlags.from(header_flags)) {
            .ack => .{ .ack = AcknowledgeList.from(allocator, raw) },
            .nack => .{ .nack = AcknowledgeList.from(allocator, raw) },
            .datagram => blk: {
                // reset to the beginning of the packet
                stream.reset();
                const flags = try reader.readByte();
                const sequence_number = try reader.readIntLittle(u24);
                var frames = std.ArrayList(Frame).init(allocator);
                while (try stream.getPos() < try stream.getEndPos()) {
                    try frames.append(try Frame.from(reader, allocator));
                }
                break :blk .{ .datagram = .{ .flags = flags, .sequence_number = sequence_number, .frames = frames } };
            },
        };
    }
};
