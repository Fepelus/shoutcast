//! Main creates a threadpool, reads the Config, starts the Server and then
//! for each Connection, loops through the Directories and each Mp3File in
//! the directory sending the data to the Connection (which itself knows
//! the Protocol that should be on the wire)
const srvr = @import("server.zig");
const dir = @import("directory.zig");
const cfg = @import("config.zig");
const supply = @import("dir_supply.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;


pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();
    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(std.Thread.Pool.Options{
        .allocator = allocator,
        .n_jobs = 2
    });
    defer thread_pool.deinit();

    const config = try cfg.Config.init(allocator);
    defer config.destroy();
    var server = try srvr.Server.init(allocator, "0.0.0.0", config.port);
    defer server.destroy();
    try server.listen();
    while (true) {
        try thread_pool.spawn(safe_handle_connection, .{allocator, server, config});
    }
}

fn safe_handle_connection(allocator: Allocator, server: srvr.Server, config: cfg.Config) void {
    handle_connection(allocator, server, config) catch |err| {
        std.log.err("Error: {}\n", .{err});
    };
}
fn handle_connection(allocator: Allocator, server: srvr.Server, config: cfg.Config) !void {
    var connection = try server.accept();
    defer connection.destroy();

    try connection.ignoreReadFromClient();
    try connection.sendPreamble();

    var dir_supply  = supply.DirectorySupply.init(allocator, config);
    while (dir_supply.has_next()) {
        var directory = try dir_supply.next();
        defer directory.destroy();
        while (try directory.next()) | mp3_file| {
            defer mp3_file.destroy();
            try connection.send(mp3_file.trackinfo(), mp3_file.bytes());
        }
    }
}
