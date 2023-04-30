const std = @import("std");
const network = @import("network");
const RakNetError = @import("raknet.zig").RakNetError;
const RakNetMagic = @import("raknet.zig").RakNetMagic;

pub fn verify_magic(reader: anytype) RakNetError!void {
    const received_magic = try reader.readBoundedBytes(RakNetMagic.len);
    if (!std.mem.eql(u8, &RakNetMagic, received_magic.buffer[0..received_magic.len])) {
        return RakNetError.InvalidMagic;
    }
}

pub fn read_address(reader: anytype) !network.EndPoint {
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

pub fn write_address(writer: anytype, endpoint: network.EndPoint) !void {
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
            try writer.writeIntBig(u32, 0);
        },
    };
}
