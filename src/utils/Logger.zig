const std = @import("std");
const Self = @This();

/// Whether to emit messages to std.log
verbose: bool = false,

/// Emits an error message if the verbose flag is set
pub fn err(self: *Self, comptime format: []const u8, args: anytype) void {
    self.log(.err, format, args);
}

/// Emits an info message if the verbose flag is set
pub fn info(self: *Self, comptime format: []const u8, args: anytype) void {
    self.log(.info, format, args);
}

/// Emits a warning message if the verbose flag is set
pub fn warn(self: *Self, comptime format: []const u8, args: anytype) void {
    self.log(.warn, format, args);
}

/// Emits a debug message if the verbose flag is set
pub fn debug(self: *Self, comptime format: []const u8, args: anytype) void {
    self.log(.debug, format, args);
}

/// Emits a log message if the verbose flag is set
inline fn log(self: *Self, comptime level: std.log.Level, comptime format: []const u8, args: anytype) void {
    if (self.verbose) {
        switch (level) {
            inline else => @call(
                .auto,
                @field(std.log, @tagName(level)),
                .{ format, args },
            ),
        }
    }
}
