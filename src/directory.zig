//! When initialised with the path of a directory, will iterate through all
//! files within it that end with ".mp3" yielding Mp3File objects in order
//! sorted by name
const std = @import("std");
const mp3f = @import("mp3_file.zig");

pub const Directory = struct {
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    files: [][]const u8,
    index: u8,

    pub fn init(allocator: std.mem.Allocator, dirname: []const u8) !Directory {
        const dir = try std.fs.cwd().openDir(
            dirname,
            .{ .iterate = true },
        );
        var iterator = dir.iterate();
        var files = std.ArrayList([]const u8).init(allocator);
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and endsInMp3(entry.name)) {
                const namecopy = try allocator.alloc(u8, entry.name.len);
                @memcpy(namecopy, entry.name);
                try files.append(namecopy);
            }
        }
        sortStringSlice(files.items);
        return Directory{
            .allocator = allocator,
            .dir = dir,
            .files = try files.toOwnedSlice(),
            .index = 0,
        };
    }

    pub fn next(self: *Directory) !?mp3f.Mp3File {
        if (self.files.len <= self.index) {
            return null;
        }
        const filename = self.files[self.index];
        self.index += 1;

        const fullFilename = try self.dir.realpathAlloc(self.allocator, filename);
        defer self.allocator.free(fullFilename);
        return try mp3f.Mp3File.init(self.allocator,fullFilename);
    }

    pub fn destroy(self: Directory) void {
        for (self.files) |filename| {
            self.allocator.free(filename);
        }
        self.allocator.free(self.files);
    }

};

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn sortStringSlice(slice: [][]const u8) void {
    std.mem.sort([]const u8, slice, {}, lessThan);
}

fn endsInMp3(name:[]const u8) bool {
    const l = name.len;
    return std.mem.eql(u8, ".mp3", name[l-4..]);
}
