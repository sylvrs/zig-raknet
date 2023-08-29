const std = @import("std");

pub const Order = struct { index: u24, channel: u8 };
pub const Fragment = struct { count: u32, fragment_id: u16, index: u32 };
pub const Reliability = enum(u8) {
    const Self = @This();
    Unreliable = 0,
    UnreliableSequenced = 1,
    Reliable = 2,
    ReliableOrdered = 3,
    ReliableSequenced = 4,
    UnreliableWithAckReceipt = 5,
    ReliableWithAckReceipt = 6,
    ReliableOrderedWithAckReceipt = 7,

    pub fn fromFlags(flags: u8) !Self {
        return try std.meta.intToEnum(Reliability, flags >> 5);
    }
};

pub const Frame = union(enum) {
    const HasFragmentFlag = 0x10;

    Unreliable: struct { fragment: ?Fragment, body: []const u8 },
    UnreliableSequenced: struct { sequence_index: u24, fragment: ?Fragment, body: []const u8 },
    Reliable: struct { message_index: u24, fragment: ?Fragment, body: []const u8 },
    ReliableOrdered: struct { message_index: u24, order: Order, fragment: ?Fragment, body: []const u8 },

    fn readFragmentFromFlags(flags: u8, reader: anytype) !?Fragment {
        if (flags & HasFragmentFlag != 0) {
            return .{
                .count = try reader.readIntBig(u32),
                .fragment_id = try reader.readIntBig(u16),
                .index = try reader.readIntBig(u32),
            };
        } else {
            return null;
        }
    }

    pub fn fragment(self: Frame) !?Fragment {
        return switch (self) {
            inline else => |frame| frame.fragment,
        };
    }

    pub fn body(self: Frame) ![]const u8 {
        return switch (self) {
            inline else => |frame| frame.body,
        };
    }

    pub fn readBuffer(reader: anytype, size: usize, allocator: std.mem.Allocator) ![]const u8 {
        const allocated_buffer: []u8 = try allocator.alloc(u8, size);
        const bytes_read = try reader.readAll(allocated_buffer);
        return allocated_buffer[0..bytes_read];
    }

    pub fn from(reader: anytype, allocator: std.mem.Allocator) !Frame {
        const flags = try reader.readByte();
        const buffer_size = try reader.readIntBig(u16) + 7 << 3;
        // make sure to free after use
        return switch (try Reliability.fromFlags(flags)) {
            .Unreliable => {
                return .{ .Unreliable = .{
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                } };
            },
            .UnreliableSequenced => {
                return .{ .UnreliableSequenced = .{
                    .sequence_index = try reader.readIntLittle(u24),
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                } };
            },
            .Reliable => {
                return .{ .Reliable = .{
                    .message_index = try reader.readIntLittle(u24),
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                } };
            },
            .ReliableOrdered => {
                return .{ .ReliableOrdered = .{
                    .message_index = try reader.readIntLittle(u24),
                    .order = .{
                        .index = try reader.readIntLittle(u24),
                        .channel = try reader.readByte(),
                    },
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                } };
            },
            else => unreachable,
        };
    }
};
