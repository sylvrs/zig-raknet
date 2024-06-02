const std = @import("std");

pub const Order = struct { index: u24, channel: u8 };
pub const Fragment = struct { count: u32, fragment_id: u16, index: u32 };
pub const Reliability = enum(u3) {
    unreliable = 0,
    unreliable_sequenced = 1,
    reliable = 2,
    reliable_ordered = 3,
    reliable_sequenced = 4,
    unreliable_with_ack_receipt = 5,
    reliable_with_ack_receipt = 6,
    reliabled_ordered_with_ack_receipt = 7,

    pub fn fromFlags(flags: u8) !Reliability {
        return try std.meta.intToEnum(Reliability, flags >> 5);
    }
};

pub const Frame = union(enum) {
    const HasFragmentFlag = 0x10;

    unreliable: struct { fragment: ?Fragment, body: []const u8 },
    unreliable_sequenced: struct { sequence_index: u24, fragment: ?Fragment, body: []const u8 },
    reliable: struct { message_index: u24, fragment: ?Fragment, body: []const u8 },
    reliable_ordered: struct { message_index: u24, order: Order, fragment: ?Fragment, body: []const u8 },

    fn readFragmentFromFlags(flags: u8, reader: anytype) !?Fragment {
        if (flags & HasFragmentFlag == 0) {
            return null;
        }
        return .{
            .count = try reader.readInt(u32, .big),
            .fragment_id = try reader.readInt(u16, .big),
            .index = try reader.readInt(u32, .big),
        };
    }

    /// Returns the fragment information for the frame
    pub fn fragment(self: Frame) ?Fragment {
        return switch (self) {
            inline else => |frame| frame.fragment,
        };
    }

    /// Returns the body of the frame
    pub fn body(self: Frame) []const u8 {
        return switch (self) {
            inline else => |frame| frame.body,
        };
    }

    /// Attempts to read a buffer from the given reader
    fn readBuffer(reader: anytype, size: usize, allocator: std.mem.Allocator) ![]const u8 {
        const allocated_buffer = try allocator.alloc(u8, size);
        errdefer allocator.free(allocated_buffer);
        const bytes_read = try reader.readAll(allocated_buffer);
        if (bytes_read != size) {
            return error.ByteCountMismatch;
        }
        return allocated_buffer;
    }

    /// Attempts to read a frame from the given reader
    pub fn from(reader: anytype, allocator: std.mem.Allocator) !Frame {
        const flags = try reader.readByte();
        // to get the size, we read two bytes, align it, and then shift right by 3
        // this is equivalent to dividing by 8 and rounding up
        const buffer_size = try reader.readInt(u16, .big) + 7 >> 3;
        return switch (try Reliability.fromFlags(flags)) {
            .unreliable => .{
                .unreliable = .{
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                },
            },
            .unreliable_sequenced => .{
                .unreliable_sequenced = .{
                    .sequence_index = try reader.readInt(u24, .little),
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                },
            },
            .reliable => .{
                .reliable = .{
                    .message_index = try reader.readInt(u24, .little),
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                },
            },
            .reliable_ordered => .{
                .reliable_ordered = .{
                    .message_index = try reader.readInt(u24, .little),
                    .order = .{
                        .index = try reader.readInt(u24, .little),
                        .channel = try reader.readByte(),
                    },
                    .fragment = try readFragmentFromFlags(flags, reader),
                    .body = try readBuffer(reader, buffer_size, allocator),
                },
            },
            inline else => error.UnsupportedReliability,
        };
    }
};

pub const FrameBuilder = struct {
    /// The allocator used to store the frames
    allocator: std.mem.Allocator,
    /// The frames received
    frames: std.ArrayList(Frame),
    /// The frame count needed to complete the message
    count: usize,

    /// `init` initializes the builder with the given allocator and frame count
    pub fn init(allocator: std.mem.Allocator, count: usize) !FrameBuilder {
        return .{
            .allocator = allocator,
            .frames = try std.ArrayList(Frame).init(allocator),
            .count = count,
        };
    }

    /// `add` adds a frame to the builder
    pub fn add(self: *FrameBuilder, frame: Frame) !?Frame {
        try self.frames.add(frame);
        if (self.frames.len == self.count) {
            return self.build();
        }
        return null;
    }

    /// `isComplete` returns true if the frame builder has all the frames needed to build the message
    pub fn isComplete(self: *FrameBuilder) bool {
        return self.frames.len == self.count;
    }
};
