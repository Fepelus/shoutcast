//! Suppies the audio content of the MP3 file and the trackinfo
//! data that mp3id3 parses from the ID3 tags
const std = @import("std");
const id3 = @import("mp3id3.zig");
const Allocator = std.mem.Allocator;

pub const Mp3File = struct {
    allocator: Allocator,
    file: std.fs.File,
    trackInfo: []u8,

    pub fn init(parent_allocator: Allocator, filename: []const u8) !Mp3File {
        std.debug.print("Loading: {s}\n", .{filename});

        const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only});
        errdefer file.close();

        const trckinf = try id3.getTrackinfo(parent_allocator, file, filename);

        return Mp3File{
            .allocator = parent_allocator,
            .file = file,
            .trackInfo = trckinf
        };
    }

    pub fn deinit(self: Mp3File) void {
       self.file.close();
       self.allocator.free(self.trackInfo);
    }

};
