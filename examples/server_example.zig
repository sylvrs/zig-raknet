const std = @import("std");
const raknet = @import("raknet");
const network = @import("network");

/// This is a Minecraft-specific server list ping format
pub const ServerNameFormat = struct {
    header: enum { mcpe, mcee },
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

    pub fn toBufString(self: ServerNameFormat, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "{s};{s};{d};{s};{d};{d};{d};{s};{s};{d};{d};{d};", .{
            switch (self.header) {
                .mcpe => "MCPE",
                .mcee => "MCEE",
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

// Define custom log configuration
pub const std_options = struct {
    pub const logFn = customLogFn;
};

pub fn customLogFn(comptime level: std.log.Level, comptime _: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    // Print the message to stderr, silently ignoring any errors
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print("[" ++ comptime level.asText() ++ "] " ++ format ++ "\n", args) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // initialize networking (required for Windows)
    try raknet.init();
    defer raknet.deinit();

    var server = raknet.Server.init(.{
        .allocator = gpa.allocator(),
        .endpoint = .{
            .address = .{ .ipv4 = try network.Address.IPv4.parse("0.0.0.0") },
            .port = 19132,
        },
        .verbose = true,
    });

    // set pong data
    server.setPongData(blk: {
        var server_name: [1024]u8 = undefined;
        // server name format
        const server_format = ServerNameFormat{
            .header = .mcpe,
            .motd = "Hello from Zig!",
            .protocol_version = 575,
            .game_version = "1.20.19",
            .player_count = 0,
            .max_player_count = 20,
            .server_guid = server.guid,
            .sub_motd = "Zig-RakNet",
            .gamemode = "Creative",
            .gamemode_numeric = 1,
            .port_ipv4 = 19132,
            .port_ipv6 = 19132,
        };
        break :blk try server_format.toBufString(&server_name);
    });
    try server.accept();
}
