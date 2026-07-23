//! Main creates a threadpool, reads the Config, starts the Server and then
//! for each Connection, loops through the Directories and each Mp3File in
//! the directory sending the data to the Connection (which itself knows
//! the Protocol that should be on the wire)
const srvr = @import("server.zig");
const prot = @import("protocol.zig");
const dir = @import("directory.zig");
const cfg = @import("config.zig");
const supply = @import("dir_supply.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const buffer_size = 64 * 1024; // bytes

pub fn main(init: std.process.Init) !void {
    var general_purpose_allocator = std.heap.DebugAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    const io = init.io;

    const config = try cfg.Config.init(gpa, io, init.minimal.environ);
    defer config.deinit();
    var server = try srvr.Server.init(gpa, io, "0.0.0.0", config.port);
    defer server.close();
    try server.listen();
    while (true) {
        const protocol = try server.accept();
        const thread = try std.Thread.spawn(.{}, safeHandleConnection, .{gpa, io, protocol, config});
        thread.detach();
    }
}

fn safeHandleConnection(allocator: Allocator, io: std.Io, protocol: prot.Protocol, config: cfg.Config) void {
    var mutable_protocol = protocol;
    defer mutable_protocol.deinit();
    handleConnection(allocator, io, &mutable_protocol, config) catch |err|
        switch (err) {
            error.OutOfMemory =>  std.debug.panic("OUT OF MEMORY\n", .{}),
            else => std.debug.print("Error: {}\n", .{err}), // otherwise don't panic — merely end this thread
        };
}
fn handleConnection(gpa: Allocator, io: std.Io, protocol: *prot.Protocol, config: cfg.Config) !void {
    const buffer = try gpa.alloc(u8, buffer_size);
    defer gpa.free(buffer);
    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(buffer);
    const allocator = fixed_buffer_allocator.allocator();

    if (!try protocol.isOKHeaderFromClient()) return;
    try protocol.sendPreamble();

    var dir_supply = supply.DirectorySupply.init(allocator, io, config);
    while (try dir_supply.next()) |in_directory| {
        var directory = in_directory;
        defer directory.deinit();
        while (try directory.next()) |mp3_file| {
            defer mp3_file.deinit();
            try protocol.sendFile(mp3_file);
        }
    }
}
