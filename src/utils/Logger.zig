const std = @import("std");
const Self = @This();
verbose: bool = false,

/// Emits an error message if the verbose flag is set
pub fn err(self: *Self, comptime format: []const u8, args: anytype) void {
    if (self.verbose) {
        std.log.err(format, args);
    }
}

/// Emits an info message if the verbose flag is set
pub fn info(self: *Self, comptime format: []const u8, args: anytype) void {
    if (self.verbose) {
        std.log.info(format, args);
    }
}

/// Emits a warning message if the verbose flag is set
pub fn warn(self: *Self, comptime format: []const u8, args: anytype) void {
    if (self.verbose) {
        std.log.warn(format, args);
    }
}

/// Emits a debug message if the verbose flag is set
pub fn debug(self: *Self, comptime format: []const u8, args: anytype) void {
    if (self.verbose) {
        std.log.debug(format, args);
    }
}
