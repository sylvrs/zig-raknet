# zig-raknet

A simple RakNet implementation in the [Zig](https://ziglang.org) programming language.

## Note

At the moment, this library only supports the master branch of Zig, meaning that it is prone to breaking changes.

## Installation

The library can be installed using Zig's package manager:

```sh
zig fetch --save "https://github.com/sylvrs/zig-raknet/archive/refs/heads/master.tar.gz" 
```

```js
// build.zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // add the dependency to the build script
    const network_module = b.dependency("network", .{ .target = target, .optimize = optimize }).module("network");
    const raknet_module = b.dependency("raknet", .{ .target = target, .optimize = optimize }).module("raknet");
    // ...
    // your executable should be defined already
    // i'll be using the name "exe" for the sake of this example
    exe.root_module.addImport("raknet", module);
    exe.root_module.addImport("network", network_module);
}
```

## Usage

Example usage of the library can be found in the `examples` directory. Here is what a simple server looks like:

```zig
const raknet = @import("raknet");
const network = @import("network");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // create a server
    var server = raknet.Server.init(.{
        // the allocator to use for the server
        .allocator = gpa.allocator(),
        // the data to be sent to clients when they ping the server
        .pong_data = "Hello, World!"
        // the address to start listening on
        .endpoint = .{
            .address = .{ .ipv4 = try network.Address.IPv4.parse("0.0.0.0") },
            .port = 19132,
        },
        // whether to print messages from the server into stderr
        .verbose = true,
    });
    defer server.deinit();
    std.debug.print("Listening to data on {any}\n", .{server.address});
    // start the server and listen for incoming connections
    try server.accept();
}
```
