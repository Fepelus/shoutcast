//! All knowledge of the shoutcast protocol.
//! When a new connection is made, its first job is to read — and ignore — the request
//! from the client. Then it sends its own header, specifying the blocksize. Then for
//! each MP3 that it is given, breaks the audio into blocks and sends each to the
//! socket. After each block the metadata is sent. There is a little bit of fiddling
//! when the end of one file does not completely fill the block and the remainder
//! has to be stored to add to the start of the next
//! block.
const std = @import("std");
const Allocator = std.mem.Allocator;

const blocksize = 24576;

pub const Protocol = struct {
    allocator: Allocator,
    socket: std.posix.socket_t,
    stream: std.net.Stream,
    remaining_to_send: []u8,

    pub fn init(allocator: Allocator, socket: std.posix.socket_t) Protocol {
        return Protocol{
            .allocator = allocator,
            .socket = socket,
            .stream = std.net.Stream{.handle = socket},
            .remaining_to_send = &[_]u8{},
        };
    }

    pub fn ignoreReadFromClient(self: Protocol) !void {
        var buf: [1]u8 = undefined;
        var count: u8 = 0;
        while (count < 4) {
        _ = try self.stream.readAtLeast(buf[0..], 1);
        if (count % 2 == 0 and buf[0] == '\r') {
            count += 1;
        } else if (count % 2 == 1 and buf[0] == '\n') {
            count += 1;
        } else {
            count = 0;
        }
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

    pub fn send(self: *Protocol, trackinfo: []u8, bytes: []u8) !void {
        var i: usize = 0; // index of the next byte to send
        if (0 < self.remaining_to_send.len) {
            const buffer = try self.allocator.alloc(u8, blocksize);
            defer self.allocator.free(buffer);

            i = blocksize - self.remaining_to_send.len;
            @memcpy(buffer[0..self.remaining_to_send.len], self.remaining_to_send);
            @memcpy(buffer[self.remaining_to_send.len..blocksize], bytes[0..i]);

            self.allocator.free(self.remaining_to_send);
            self.remaining_to_send = &[_]u8{};

            try self.stream.writeAll(buffer[0..]);
            try self.sendHeader(self.allocator, trackinfo);
        }

        while (i + blocksize <= bytes.len) {
//        std.debug.print("Sending block of size {} at byte {}\n", .{bytes_to_send, i});
            try self.stream.writeAll(bytes[i..i + blocksize]);
 //       std.debug.print("Sending header\n", .{});
            try self.sendHeader(self.allocator, trackinfo);

            i += blocksize;

            std.time.sleep(512 * std.time.ns_per_ms);
        }

        self.remaining_to_send = try self.allocator.alloc(u8, bytes.len - i);
        //std.debug.print("Bytes remaining to send: {d}\n", .{self.remaining_to_send.len});
        @memcpy(self.remaining_to_send, bytes[i..]);
    }

    fn sendHeader(self: Protocol, allocator: Allocator, trackinfo: []u8) !void {
        const prefix = "StreamTitle='";
        const suffix = "';StreamUrl='http://localhost:8000';";

        const content_len = prefix.len + trackinfo.len + suffix.len;
        var length_byte: u8 = @intCast(content_len / 16); // rounds down
        if (0 < content_len % 16 ) {
            length_byte += 1;
        }
        const header_len = length_byte * 16;
        var heap_memory = try allocator.alloc(u8, header_len+1);
        defer allocator.free(heap_memory);

        heap_memory[0] = length_byte;

        const header_memory = heap_memory[1..];
        _ = try std.fmt.bufPrint(header_memory, "{s}{s}{s}", .{ prefix, trackinfo, suffix});

        for (content_len..header_len) | i | {
            header_memory[i] = 0;
        }

        try self.stream.writeAll(heap_memory);

    }

    pub fn destroy(self: Protocol) void {
        std.posix.close(self.socket);
        self.allocator.free(self.remaining_to_send);
    }

};
