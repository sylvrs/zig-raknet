const std = @import("std");

pub const Buffer = struct {
    const BufferError = error{OutOfBounds};
    const Reader = std.io.Reader(*Buffer, BufferError, read);

    data: []const u8,
    index: usize,

    pub fn init(data: []const u8) Buffer {
        return .{ .data = data, .index = 0 };
    }

    pub fn read(self: *Buffer, bytes: []u8) BufferError!usize {
        if (self.index >= self.data.len) return BufferError.OutOfBounds;
        std.mem.copy(u8, bytes, self.data[self.index..(self.index + bytes.len)]);
        self.index += bytes.len;
        return bytes.len;
    }

    pub fn reader(self: *Buffer) Reader {
        return Reader{ .context = self };
    }
};
