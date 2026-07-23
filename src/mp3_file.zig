//! Supplies the audio content of the MP3 file and the trackinfo
//! data that mp3id3 parses from the ID3 tags
const std = @import("std");
const id3 = @import("mp3id3.zig");
const Allocator = std.mem.Allocator;

pub const Mp3File = struct {
    allocator: Allocator,
    io: std.Io,
    file: std.Io.File,
    trackInfo: []u8,

    pub fn init(parent_allocator: Allocator, io: std.Io, filename: []const u8) !Mp3File {
        std.debug.print("Loading: {s}\n", .{filename});

        const file = try std.Io.Dir.cwd().openFile(io, filename, .{ .mode = .read_only});
        errdefer file.close(io);

        const trckinf = try id3.getTrackinfo(parent_allocator, io, file, filename);

        return Mp3File{
            .allocator = parent_allocator,
            .io = io,
            .file = file,
            .trackInfo = trckinf
        };
    }

    pub fn deinit(self: Mp3File) void {
       self.file.close(self.io);
       self.allocator.free(self.trackInfo);
    }

};
