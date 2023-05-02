const std = @import("std");
const network = @import("network");
const RakNetError = @import("raknet.zig").RakNetError;
const RakNetMagic = @import("raknet.zig").RakNetMagic;

pub fn verifyMagic(reader: anytype) RakNetError!void {
    const received_magic = try reader.readBoundedBytes(RakNetMagic.len);
    if (!std.mem.eql(u8, &RakNetMagic, received_magic.buffer[0..received_magic.len])) {
        return RakNetError.InvalidMagic;
    }
}

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

pub fn writeAddress(writer: anytype, endpoint: network.EndPoint) !void {
    return switch (endpoint.address) {
        .ipv4 => {
            try writer.writeByte(4);
            try writer.writeAll(&endpoint.address.ipv4.value);
            try writer.writeIntBig(u16, endpoint.port);
        },
        .ipv6 => {
            try writer.writeByte(6);
            // AF_INET6
            try writer.writeIntLittle(i16, std.os.AF.INET6);
            try writer.writeIntBig(i16, @intCast(i16, endpoint.port));
            // flow info
            try writer.writeIntBig(u32, 0);
            try writer.writeAll(&endpoint.address.ipv6.value);
            // scope id
            try writer.writeIntBig(u32, endpoint.address.ipv6.scope_id);
        },
    };
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
    const read_buffer = [_]u8{ 0x06, 0x17, 0x00, 0x30, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x0a };
    var stream = std.io.fixedBufferStream(&read_buffer);
    const reader = stream.reader();
    // read address
    const endpoint = try readAddress(reader);
    // check that the read address is correct
    try std.testing.expectEqual(endpoint, expected);
}

test "correctly write IPv6 address" {
    const expected = [_]u8{ 0x06, 0x17, 0x00, 0x30, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x0a };
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
