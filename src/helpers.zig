const std = @import("std");
const network = @import("network");
const RakNetError = @import("raknet.zig").RakNetError;
const RakNetMagic = @import("raknet.zig").RakNetMagic;

/// Writes a string to the writer.
pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeIntBig(u16, @intCast(value.len));
    try writer.writeAll(value);
}

/// Reads a string from the reader into the buffer.
pub fn readStringBuffer(reader: anytype, buffer: []u8) !usize {
    const length = try reader.readIntBig(u16);
    const read_bytes = try reader.readAtLeast(buffer, length);
    if (read_bytes != length) {
        return error.MismatchedStringLength;
    }
    return length;
}

/// Verifies that the magic bytes read from the current position of the reader match the expected magic bytes.
pub fn verifyMagic(reader: anytype) RakNetError!void {
    const received_magic = try reader.readBoundedBytes(RakNetMagic.len);
    if (!std.mem.eql(u8, RakNetMagic, received_magic.buffer[0..received_magic.len])) {
        return RakNetError.InvalidMagic;
    }
}

/// Reads a network endpoint (ip + port) from the reader.
pub fn readAddress(reader: anytype) !network.EndPoint {
    const address_family = try reader.readByte();
    return switch (address_family) {
        4 => {
            const bytes = try reader.readBoundedBytes(4);
            const port = try reader.readIntBig(u16);

            return network.EndPoint{
                .address = .{
                    .ipv4 = network.Address.IPv4.init(bytes.buffer[0], bytes.buffer[1], bytes.buffer[2], bytes.buffer[3]),
                },
                .port = port,
            };
        },
        6 => {
            // AF_INET6
            _ = try reader.readIntLittle(i16);
            const port = try reader.readIntBig(u16);
            // flow info
            _ = try reader.readIntBig(u32);
            const bytes = try reader.readBoundedBytes(16);
            // scope id
            const scope_id = try reader.readIntBig(u32);
            return network.EndPoint{
                .address = .{
                    .ipv6 = network.Address.IPv6.init(bytes.buffer[0..].*, scope_id),
                },
                .port = port,
            };
        },
        else => unreachable,
    };
}

/// Writes a network endpoint (ip + port) to the writer.
pub fn writeAddress(writer: anytype, endpoint: network.EndPoint) !void {
    return switch (endpoint.address) {
        .ipv4 => |ipv4| {
            try writer.writeByte(4);
            try writer.writeAll(&ipv4.value);
            try writer.writeIntBig(u16, endpoint.port);
        },
        .ipv6 => |ipv6| {
            try writer.writeByte(6);
            // AF_INET6
            try writer.writeIntLittle(i16, std.os.AF.INET6);
            try writer.writeIntBig(i16, @as(i16, @intCast(endpoint.port)));
            // flow info
            try writer.writeIntBig(u32, 0);
            try writer.writeAll(&ipv6.value);
            // scope id
            try writer.writeIntBig(u32, ipv6.scope_id);
        },
    };
}

test "write string correctly" {
    const value = "test string";
    const expected = [_]u8{ 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x73, 0x74, 0x72, 0x69, 0x6e, 0x67 };
    // allocate a small buffer
    const allocator: std.mem.Allocator = std.testing.allocator;
    var write_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(write_buffer);
    // create stream & writer
    var stream = std.io.fixedBufferStream(write_buffer);
    const writer = stream.writer();
    // write string
    try writeString(writer, value);
    // check that the written bytes are correct
    try std.testing.expectEqualSlices(u8, &expected, stream.getWritten());
}

test "read string using buffer correctly" {
    const expected = "test string";
    // create stream & reader
    const read_buffer = [_]u8{ 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x73, 0x74, 0x72, 0x69, 0x6e, 0x67 };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    // read string into buffer
    var buffer = [_]u8{0} ** 1024;
    const size = try readStringBuffer(reader, &buffer);
    const value = buffer[0..size];
    // check that the read string is correct
    try std.testing.expectEqualStrings(expected, value);
}

test "correctly verify magic" {
    const read_buffer = [_]u8{ 0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78 };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    try verifyMagic(reader);
}

test "correctly fail to verify magic" {
    const read_buffer = [_]u8{ 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    try std.testing.expectError(RakNetError.InvalidMagic, verifyMagic(reader));
}

test "correctly read IPv4 address" {
    const expected = network.EndPoint{ .address = .{ .ipv4 = network.Address.IPv4.init(127, 0, 0, 1) }, .port = 12345 };
    // create stream & reader
    const read_buffer = [_]u8{ 4, 127, 0, 0, 1, 0x30, 0x39 };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    // read address
    const endpoint = try readAddress(reader);
    // check that the read address is correct
    try std.testing.expectEqual(endpoint, expected);
}

test "correctly write IPv4 address" {
    const expected = [_]u8{ 4, 127, 0, 0, 1, 0x30, 0x39 };
    // allocate a small buffer
    const allocator: std.mem.Allocator = std.testing.allocator;
    var write_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(write_buffer);
    // create stream & writer
    var stream = std.io.fixedBufferStream(write_buffer);
    const writer = stream.writer();
    // create endpoint & write address
    const endpoint = network.EndPoint{ .address = .{ .ipv4 = network.Address.IPv4.init(127, 0, 0, 1) }, .port = 12345 };
    try writeAddress(writer, endpoint);
    // check that the written bytes are correct
    try std.testing.expectEqualSlices(u8, &expected, stream.getWritten());
}

test "correctly read IPv6 address" {
    // create endpoint & write address
    const expected = network.EndPoint{
        .address = .{
            .ipv6 = network.Address.IPv6.init([16]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f }, 10),
        },
        .port = 12345,
    };
    // create stream & reader
    const read_buffer = [_]u8{ 0x06, std.os.AF.INET6, 0x00, 0x30, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x0a };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    // read address
    const endpoint = try readAddress(reader);
    // check that the read address is correct
    try std.testing.expectEqual(endpoint, expected);
}

test "correctly write IPv6 address" {
    const expected = [_]u8{ 0x06, std.os.AF.INET6, 0x00, 0x30, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x0a };
    // allocate a small buffer
    const allocator: std.mem.Allocator = std.testing.allocator;
    var write_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(write_buffer);
    // create stream & writer
    var stream = std.io.fixedBufferStream(write_buffer);
    const writer = stream.writer();
    // create endpoint & write address
    const endpoint = network.EndPoint{
        .address = .{
            .ipv6 = network.Address.IPv6.init([16]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f }, 10),
        },
        .port = 12345,
    };
    try writeAddress(writer, endpoint);
    // check that the written bytes are correct
    try std.testing.expectEqualSlices(u8, &expected, stream.getWritten());
}
