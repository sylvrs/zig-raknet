const std = @import("std");

const Self = @This();

/// A drop-in set replacement used for tracking which packets have been received.
pub const Set = std.AutoHashMap(usize, void);

const RecordType = enum(u1) { single = 0, range = 1 };
/// A list of packet IDs that are sent between the client and server.
packets: std.ArrayList(u24),

/// Decodes a buffer into an Acknowledge packet (This can be an ACK or NACK)
pub fn from(allocator: std.mem.Allocator, raw: []const u8) Self {
    _ = raw;
    const packets = std.ArrayList(u24).init(allocator);
    return Self{ .packets = packets };
}
