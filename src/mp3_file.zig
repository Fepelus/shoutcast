//! Suppies the audio content of the MP3 file and the trackinfo
//! data that mp3id3 parses from the ID3 tags
const std = @import("std");
const id3 = @import("mp3id3.zig");
const Allocator = std.mem.Allocator;

pub const Mp3File = struct {
    memory: []u8,
    trackInfo: []u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, filename: []const u8) !Mp3File {
        std.debug.print("Loading: {s}\n", .{filename});
        var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only});
        defer file.close();

        const file_size: u64 = (try file.stat()).size;
        const buffer = try allocator.alloc(u8, @intCast(file_size));
        try file.reader().readNoEof(buffer);

        return Mp3File{
            .memory = buffer,
            .allocator = allocator,
            .trackInfo = try id3.get_trackinfo(allocator, buffer)
        };
    }

    pub fn trackinfo(self: Mp3File) []u8 {
        return self.trackInfo;
    }

    pub fn bytes(self: Mp3File) []u8 {
        return self.memory;
    }

    pub fn destroy(self: Mp3File) void {
       self.allocator.free(self.trackInfo);
       self.allocator.free(self.memory);
    }

};
