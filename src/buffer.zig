const std = @import("std");

fn Buffer(comptime T: type) type {
    return struct {
        const BufferError = error{OutOfBounds};
        const Reader = std.io.Reader(*Buffer(T), BufferError, read);
        const Writer = std.io.Writer(*Buffer(T), BufferError, write);

        data: T,
        index: usize,

        pub fn init(data: T) Buffer(T) {
            return .{ .data = data, .index = 0 };
        }

        pub fn read(self: *Buffer(T), bytes: []u8) BufferError!usize {
            if (self.index >= self.data.len) return BufferError.OutOfBounds;
            std.mem.copy(u8, bytes, self.data[self.index..(self.index + bytes.len)]);
            self.index += bytes.len;
            return bytes.len;
        }

        pub fn write(self: *Buffer(T), bytes: []const u8) BufferError!usize {
            if (self.index >= self.data.len) return BufferError.OutOfBounds;
            std.mem.copy(u8, self.data[self.index..(self.index + bytes.len)], bytes);
            self.index += bytes.len;
            return bytes.len;
        }

        pub fn reader(self: *Buffer(T)) Reader {
            return Reader{ .context = self };
        }

        pub fn writer(self: *Buffer(T)) Writer {
            return Writer{ .context = self };
        }
    };
}

// todo: are there better ways to do this?
// i'd like to make the data mutable for the most flexibility
pub const ReadableBuffer = Buffer([]const u8);
pub const WriteableBuffer = Buffer([]u8);