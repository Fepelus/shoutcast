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
const net = std.Io.net;

const blocksize = 24576; // bytes
const blocksleep = 704; // ms
const read_buffer_size = 512;
const write_buffer_size = 4096;

pub const Protocol = struct {
    allocator: Allocator,
    io: std.Io,
    stream: net.Stream,
    reader: net.Stream.Reader,
    writer: net.Stream.Writer,
    read_buffer: []u8,
    write_buffer: []u8,
    buffer: []u8,
    index_to_fill: usize,

    pub fn init(allocator: Allocator, io: std.Io, stream: net.Stream) !Protocol {
        const read_buffer = try allocator.alloc(u8, read_buffer_size);
        const write_buffer = try allocator.alloc(u8, write_buffer_size);
        return Protocol{
            .allocator = allocator,
            .io = io,
            .stream = stream,
            .reader = net.Stream.Reader.init(stream, io, read_buffer),
            .writer = net.Stream.Writer.init(stream, io, write_buffer),
            .read_buffer = read_buffer,
            .write_buffer = write_buffer,
            .buffer = try allocator.alloc(u8, blocksize),
            .index_to_fill = 0,
        };
    }

    pub fn isOKHeaderFromClient(self: *Protocol) !bool {
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
            const byte = self.reader.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => return false,
                else => return err,
            };

            if (endHeader[endCount] == byte) endCount += 1
            else endCount = 0;
            if (endCount == endHeader.len) return result;

            if (result and badAccept[badCount] == byte) badCount += 1
            else badCount = 0;
            if (badCount == badAccept.len) result = false;
        }
    }

    pub fn sendPreamble(self: *Protocol) !void {
        const prefix = "ICY 200 OK\r\nicy-notice1: <BR>This stream requires<a href=\"http://www.winamp.com/\">Winamp</a><BR>\r\nicy-notice2: Paddy Shoutcast server<BR>\r\nicy-name: Paddy Shoutcast server\r\nicy-genre: Pop Top 40 Dance Rock\r\nicy-url: http://localhost:8000\r\ncontent-type: audio/mpeg\r\nicy-pub: 1\r\nicy-metaint: ";
        const suffix = "\r\nicy-br: 96\r\n\r\n";

        var list = std.array_list.Managed(u8).init(self.allocator);
        defer list.deinit();

        try list.print("{s}{d}{s}", .{prefix, blocksize, suffix});
        try self.writer.interface.writeAll(list.items);
        try self.writer.interface.flush();
    }

    pub fn sendFile(self: *Protocol, mp3_file: mp3f.Mp3File) !void {
        errdefer self.index_to_fill = 0;
        while (true) {
            const bytes_read = try mp3_file.file.readStreaming(mp3_file.io, &.{self.buffer[self.index_to_fill..]});
            if (bytes_read < blocksize - self.index_to_fill) {
                self.index_to_fill = bytes_read;
                return;
            }

            self.index_to_fill = 0;

            try self.writer.interface.writeAll(self.buffer);
            try self.writer.interface.flush();
            try self.sendHeader(mp3_file.trackInfo);

            try self.io.sleep(.fromMilliseconds(blocksleep), .awake);
        }
    }

    fn sendHeader(self: *Protocol, trackinfo: []u8) !void {
        const prefix = "StreamTitle='";
        const suffix = "';StreamUrl='http://localhost:8000';";
        const maximumTrackinfoLen = 254 * 16 - (prefix.len + suffix.len);

        var trackinfoLen: usize = trackinfo.len;
        if (maximumTrackinfoLen < trackinfoLen) {
            trackinfoLen = maximumTrackinfoLen;
        }

        const content_len: usize = prefix.len + trackinfoLen + suffix.len;
        var length_byte: u8 = @intCast(content_len / 16);
        const short_content_len: u8 = @intCast(content_len % 16);
        if (0 < short_content_len % 16 ) {
            length_byte += 1;
        }
        const header_len: u16 = @as(u16, length_byte) * 16;
        var heap_memory = try self.allocator.alloc(u8, header_len+1);
        defer self.allocator.free(heap_memory);

        heap_memory[0] = length_byte;

        const header_memory = heap_memory[1..];
        _ = try std.fmt.bufPrint(header_memory, "{s}{s}{s}", .{ prefix, trackinfo[0..trackinfoLen], suffix});

        for (content_len..header_len) | i | {
            header_memory[i] = 0;
        }

        try self.writer.interface.writeAll(heap_memory);
        try self.writer.interface.flush();

    }

    pub fn deinit(self: *Protocol) void {
        self.stream.close(self.io);
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
        self.allocator.free(self.buffer);
    }

};
