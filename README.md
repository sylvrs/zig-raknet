# zig-raknet

A simple RakNet server implementation in the [Zig](https://ziglang.org) programming language.

## Usage

Example usage of the library can be found in the `examples` directory. Here is what a simple server looks like:

```c
pub fn main() !void {
    // create a server
    var server = try raknet.Server.init(
        std.heap.page_allocator,
        .{
            .address = .{ .ipv4 = try network.Address.IPv4.parse("127.0.0.1") },
            .port = 19132,
        },
    );
    defer server.deinit();
    std.debug.print("Listening to data on {any}\n", .{server.address});
    // start the server and listen for incoming connections
    try server.start();
}
```
