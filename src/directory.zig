//! When initialised with the path of a directory, will iterate through all
//! files within it that end with ".mp3" yielding Mp3File objects in order
//! sorted by name
const std = @import("std");
const mp3f = @import("mp3_file.zig");

pub const Directory = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    files: [][]const u8,
    index: u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, dirname: []const u8) !Directory {
        var dir = try std.Io.Dir.cwd().openDir(
            io,
            dirname,
            .{ .iterate = true },
        );
        errdefer dir.close(io);

        var files = std.array_list.Managed([]const u8).init(allocator);
        errdefer {
            for (files.items) |f| allocator.free(f);
            files.deinit();
        }

        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            if (entry.kind == .file and endsInMp3(entry.name)) {
                const namecopy = try allocator.dupe(u8, entry.name);
                try files.append(namecopy);
            }
        }

        sortStringSlice(files.items);

        return Directory{
            .allocator = allocator,
            .io = io,
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

        const fullFilename = try self.dir.realPathFileAlloc(self.io, filename, self.allocator);
        defer self.allocator.free(fullFilename);
        return try mp3f.Mp3File.init(self.allocator, self.io, fullFilename);
    }

    pub fn deinit(self: *Directory) void {
        for (self.files) |filename| {
            self.allocator.free(filename);
        }
        self.allocator.free(self.files);
        self.dir.close(self.io);
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
