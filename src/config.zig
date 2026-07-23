//! Finds a config file at either whatever is in the SHOUTCAST_CONFIGFILE
//! environment variable or $HOME/.config/shoutcast/shoutcast.cfg.
//! It then parses it and and returns a struct with the configuration.
//! An example config file is at res/shoutcast.cfg
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Config = struct {
    allocator: Allocator,
    /// The port that this server will bind to
    port: u16,
    /// If true then this server will play each album specified once one after
    /// the other in order and then halt. If false then will play forever,
    /// choosing the next album randomly from the list of albums.
    inorder: bool,
    /// The paths of the directories to play from.
    albums: [][]const u8,

    pub fn init(allocator: Allocator, io: std.Io, environ: std.process.Environ) !Config {

        const config_path =  getFromEnvironmentVariable(allocator, environ, "SHOUTCAST_CONFIGFILE")
            catch  try getFromHomeDirectory(allocator, environ, "/.config/shoutcast/shoutcast.cfg");
        defer allocator.free(config_path);

        var albums = std.array_list.Managed([]const u8).init(allocator);
        var port: u16 = 8888;
        var inorder = false;

        const file = try std.Io.Dir.cwd().openFile(io, config_path, .{ .mode = .read_only });
        defer file.close(io);

        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &read_buffer);
        const content = try file_reader.interface.allocRemaining(allocator, .limited(512 * 1_204));
        defer allocator.free(content);

        var it = std.mem.splitAny(u8, content, "\n");
        while (it.next()) |line| {
            if (std.mem.indexOfPos(u8, line, 0, ": ") != null) {
                var key_it = std.mem.splitSequence(u8, line, ": ");
                const key = key_it.next() orelse continue;
                const value = key_it.next() orelse continue;

                if (std.mem.eql(u8, key, "port")) {
                    port = std.fmt.parseInt(u16, value, 10) catch |err| {
                        std.debug.print("Error parsing port ({s}): {}\n", .{value, err});
                        return err;
                    };
                } else if (std.mem.eql(u8, key, "inorder")) {
                    inorder = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "album")) {
                    const album_memory = try allocator.alloc(u8, value.len);
                    @memcpy(album_memory, value);
                    try albums.append(album_memory);
                }
            }
        }

        return Config{
           .allocator = allocator,
           .port = port,
           .inorder = inorder,
           .albums = try albums.toOwnedSlice(),
        };
    }

    pub fn deinit(self: Config) void {
        for (self.albums) |album| {
            self.allocator.free(album);
        }
        self.allocator.free(self.albums);
    }
};

fn getFromEnvironmentVariable(allocator: Allocator, environ: std.process.Environ, env_name: []const u8) ![]u8 {
    return try environ.getAlloc(allocator, env_name);
}

fn getFromHomeDirectory(allocator: Allocator, environ: std.process.Environ, file_name: []const u8) ![]u8 {
    const home_dir = try environ.getAlloc(allocator, "HOME");
    defer allocator.free(home_dir);
    const buffer = try allocator.alloc(u8, home_dir.len + file_name.len);
    @memcpy(buffer[0..home_dir.len], home_dir);
    @memcpy(buffer[home_dir.len..], file_name);
    return buffer;
}
