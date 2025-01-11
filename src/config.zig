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

    pub fn init(allocator: Allocator) !Config {

        const config_path =  getFromEnvironmentVariable(allocator, "SHOUTCAST_CONFIGFILE")
            catch  try getFromHomeDirectory(allocator, "/.config/shoutcast/shoutcast.cfg");
        defer allocator.free(config_path);

        var albums = std.ArrayList([]const u8).init(allocator);
        var port: u16 = 8888;
        var inorder = false;

        const file = try std.fs.cwd().openFile(config_path, .{ .mode = .read_only });
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 512 * 1_204);
        defer allocator.free(content);

        var it = std.mem.split(u8, content, "\n");
        while (it.next()) |line| {
            if (std.mem.indexOfPos(u8, line, 0, ": ") != null) {
                var key_it = std.mem.split(u8, line, ": ");
                const key = key_it.next() orelse continue;
                const value = key_it.next() orelse continue;

                if (std.mem.eql(u8, key, "port")) {
                    port = std.fmt.parseInt(u16, value, 10) catch |err| {
                        std.debug.print("Error parsing port: {}\n", .{err});
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

fn getFromEnvironmentVariable(allocator: Allocator, env_name: []const u8) ![]u8 {
    return try std.process.getEnvVarOwned(allocator, env_name);
}

fn getFromHomeDirectory(allocator: Allocator, file_name: []const u8) ![]u8 {
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);
    const buffer = try allocator.alloc(u8, home_dir.len + file_name.len);
    @memcpy(buffer[0..home_dir.len], home_dir);
    @memcpy(buffer[home_dir.len..], file_name);
    return buffer;
}
