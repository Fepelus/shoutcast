//! All knowledge of the shoutcast protocol.
//! When a new connection is made, its first job is to read the request from the
//! client. Then it sends its own header, specifying the blocksize. Then for each
//! MP3 that it is given, breaks the audio into blocks and sends each to the
//! socket. After each block the metadata is sent. There is a little bit of fiddling
//! when the end of one file does not completely fill the block and the remainder
//! has to be stored to add to the start of the next block.
const std = @import("std");
const mp3f = @import("mp3_file.zig");
const Allocator = std.mem.Allocator;

const blocksize = 24576; // bytes
const blocksleep = 512; // ms

pub const Protocol = struct {
    allocator: Allocator,
    socket: std.posix.socket_t,
    stream: std.net.Stream,
    buffer: []u8,
    index_to_fill: usize,

    pub fn init(allocator: Allocator, socket: std.posix.socket_t) !Protocol {
        return Protocol{
            .allocator = allocator,
            .socket = socket,
            .stream = std.net.Stream{.handle = socket},
            .buffer = try allocator.alloc(u8, blocksize),
            .index_to_fill = 0,
        };
    }

    pub fn isOKHeaderFromClient(self: Protocol) !bool {
        var buf: [1]u8 = undefined;
        const endHeader = "\r\n\r\n";
        // The app on my phone starts with two connections. One requesting
        // compressed data — which this server does not provide — and another
        // requesting uncompressed data. So here we check and refuse the one
        // that requests gzip.
        const badAccept = "Accept-Encoding: gzip";
        var endCount: u8 = 0;
        var badCount: u8 = 0;
        var result = true;
        while (true) {
            const bytes_read = try self.stream.readAtLeast(buf[0..], 1);
            if (bytes_read == 0) return false;

            if (endHeader[endCount] == buf[0]) endCount += 1
            else endCount = 0;
            if (endCount == endHeader.len) return result;

            if (result and badAccept[badCount] == buf[0]) badCount += 1
            else badCount = 0;
            if (badCount == badAccept.len) result = false;
        }
    }

    pub fn sendPreamble(self: Protocol) !void {
        const prefix = "ICY 200 OK\r\nicy-notice1: <BR>This stream requires<a href=\"http://www.winamp.com/\">Winamp</a><BR>\r\nicy-notice2: Paddy Shoutcast server<BR>\r\nicy-name: Paddy Shoutcast server\r\nicy-genre: Pop Top 40 Dance Rock\r\nicy-url: http://localhost:8000\r\ncontent-type: audio/mpeg\r\nicy-pub: 1\r\nicy-metaint: ";
        const suffix = "\r\nicy-br: 96\r\n\r\n";

        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try list.writer().print("{s}{d}{s}", .{prefix, blocksize, suffix});
        try self.stream.writeAll(list.items);
    }

    pub fn sendFile(self: *Protocol, mp3_file: mp3f.Mp3File) !void {
        errdefer self.index_to_fill = 0;
        while (true) {
            const bytes_read = try mp3_file.file.read(self.buffer[self.index_to_fill..]);
            if (bytes_read < blocksize - self.index_to_fill) {
                self.index_to_fill = bytes_read;
                return;
            }

            self.index_to_fill = 0;

            try self.stream.writeAll(self.buffer);
            try self.sendHeader(mp3_file.trackInfo);

            std.time.sleep(blocksleep * std.time.ns_per_ms);
        }
    }

    fn sendHeader(self: Protocol, trackinfo: []u8) !void {
        const prefix = "StreamTitle='";
        const suffix = "';StreamUrl='http://localhost:8000';";

        const content_len = prefix.len + trackinfo.len + suffix.len;
        var length_byte: u8 = @intCast(content_len / 16);
        if (0 < content_len % 16 ) {
            length_byte += 1;
        }
        const header_len = length_byte * 16;
        var heap_memory = try self.allocator.alloc(u8, header_len+1);
        defer self.allocator.free(heap_memory);

        heap_memory[0] = length_byte;

        const header_memory = heap_memory[1..];
        _ = try std.fmt.bufPrint(header_memory, "{s}{s}{s}", .{ prefix, trackinfo, suffix});

        for (content_len..header_len) | i | {
            header_memory[i] = 0;
        }

        try self.stream.writeAll(heap_memory);

    }

    pub fn deinit(self: Protocol) void {
        self.stream.close();
        self.allocator.free(self.buffer);
    }

};
