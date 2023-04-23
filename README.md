# zig-raknet

A simple RakNet server implementation in the [Zig](https://ziglang.org) programming language.

## Note

At the moment, this library only supports the master branch of Zig, meaning that it is prone to breaking changes.

## Installation

The library can be installed using Zig's in-progress package manager:

```js
// build.zig.zon
.{
    .name = "your-project-name",
    .version = "your-project-version",
    .dependencies = .{
        .raknet = .{
            .url = "https://github.com/sylvrs/zig-raknet/archive/refs/heads/master.tar.gz",
            // this hash value can be fetched from the error message when trying to build the project
            // there is no current way to get the hash value automatically as the package manager is
            // still very much so an *in-progress* project.
            .hash = "HASHED_VALUE_HERE",
        },
        // zig-network is used for networking
        //
        // in the future, there will be no need to install this package as the useful parts
        // of the library will be exposed in zig-raknet
        .network = .{
            .url = "https://github.com/sylvrs/zig-raknet/archive/refs/heads/master.tar.gz",
            .hash = "HASHED_VALUE_HERE",
        },
    },
}
```

## Usage

Example usage of the library can be found in the `examples` directory. Here is what a simple server looks like:

```js
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
