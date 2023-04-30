const std = @import("std");
const raknet = @import("raknet");
const network = @import("network");

/// This is a Minecraft-specific server list ping format
pub const ServerHeaderType = enum { MCPE, MCEE };
pub const ServerNameFormat = struct {
    header: ServerHeaderType,
    motd: []const u8,
    protocol_version: u32,
    game_version: []const u8,
    player_count: u32,
    max_player_count: u32,
    server_guid: i64,
    sub_motd: []const u8,
    gamemode: []const u8,
    gamemode_numeric: u8,
    port_ipv4: u32,
    port_ipv6: u32,

    pub fn toString(self: ServerNameFormat, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{s};{s};{d};{s};{d};{d};{d};{s};{s};{d};{d};{d};", .{
            switch (self.header) {
                .MCPE => "MCPE",
                .MCEE => "MCEE",
            },
            self.motd,
            self.protocol_version,
            self.game_version,
            self.player_count,
            self.max_player_count,
            self.server_guid,
            self.sub_motd,
            self.gamemode,
            self.gamemode_numeric,
            self.port_ipv4,
            self.port_ipv6,
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();
    // create a server
    var guid = rand.int(i64);
    // server name format
    const server_format = ServerNameFormat{
        .header = .MCPE,
        .motd = "Hello from Zig!",
        .protocol_version = 575,
        .game_version = "1.19.81",
        .player_count = 0,
        .max_player_count = 20,
        .server_guid = guid,
        .sub_motd = "Zig-RakNet",
        .gamemode = "Creative",
        .gamemode_numeric = 1,
        .port_ipv4 = 19132,
        .port_ipv6 = 19132,
    };
    // create buffer to store server name in
    var server_name_buf: [1024]u8 = undefined;
    // format server name using buffer
    var server_name = try server_format.toString(&server_name_buf);
    var server = try raknet.Server.init(
        gpa.allocator(),
        server_name,
        guid,
        .{
            .address = .{ .ipv4 = try network.Address.IPv4.parse("0.0.0.0") },
            .port = 19132,
        },
    );
    std.debug.print("Listening on {any}\n", .{server.address});
    try server.start();
}
