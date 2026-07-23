//! Parse the ID3 tags of an MP3 file in order to format a trackinfo
//! string that goes into the metadata of the shoutcast stream.
//! It currently handles ID3v2 then tries ID3v1 and falls back to
//! the filename
const std = @import("std");
const Allocator = std.mem.Allocator;

const tag_limit = 64 * 1024;


pub fn getTrackinfo(allocator: Allocator, io: std.Io, file: std.Io.File, filename: []const u8) ![]u8 {
    if (try attemptId3v2(allocator, io, file)) |found_id3v2| {
        return found_id3v2;
    }

    if (try attemptId3v1(allocator, io, file)) |found_id3v1| {
        return found_id3v1;
    }

    std.debug.print("No ID3 found\n",.{});
    //print_what_other_versions_are_in_the_file(file);
    var iterator = std.mem.splitBackwardsScalar(u8, filename, "/"[0]);
    return allocator.dupe(u8, iterator.first());
}

fn attemptId3v2(allocator: Allocator, io: std.Io, file: std.Io.File) !?[]u8 {
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();

    var header_buf: [14]u8 = undefined;
    const bytes_read = try file.readPositionalAll(io, &header_buf, 0);
    if (bytes_read < 14)  return null;
    if (!isID3(header_buf[0..], 0) or header_buf[3] != 3)  return null;


    const tag_size = getSynchsafeU32(header_buf[0..], 6);
    const tag_end = 10 + tag_size;
    var pos: usize = 10;

    var frame_header: [10]u8 = undefined;
    var frame_buf: [1024]u8 = undefined;

    var title: []u8 = &.{};
    var artist: []u8 = &.{};
    var album: []u8 = &.{};
    var track_number: []u8 = &.{};

    const flags = header_buf[6];
    const EXTENDED_HEADER: u8 = 0x20;
    const has_extended_header: bool = 0 < (flags & EXTENDED_HEADER);
    if (has_extended_header) {
        const extended_header_size = getSynchsafeU32(header_buf[0..], 10);
        pos += extended_header_size;
    }

    while (pos + 10 <= tag_end) {
        const frame_header_read = try file.readPositionalAll(io, &frame_header, pos);
        if (frame_header_read < 10) break;
        if (frame_header[0] == 0) break;

        const frame_size  = getSynchsafeU32(frame_header[0..], 4);
        if (frame_size == 0 or pos + 10 + frame_size > tag_end) break;

        const frame_id = frame_header[0..4];
        const should_read = std.mem.eql(u8, frame_id, "TIT2") or
            std.mem.eql(u8, frame_id, "TIT1") or
            std.mem.eql(u8, frame_id, "TPE2") or
            std.mem.eql(u8, frame_id, "TPE1") or
            std.mem.eql(u8, frame_id, "TALB") or
            std.mem.eql(u8, frame_id, "TRCK");

        if (should_read) {
            if (frame_buf.len < frame_size)  {
                pos += 10 + frame_size;
                continue;
            }

            // frame_buf starts _after_ the frame_header
            const content_read = try file.readPositionalAll(io, frame_buf[0..frame_size], pos + 10);
            if (content_read < frame_size) break;

            const text_start = indexOfText(frame_buf[0..]);

            const content = frame_buf[text_start..frame_size];

            if (std.mem.eql(u8, frame_id, "TIT2")) {
                title = try arena.dupe(u8, trim(content));
            } else if (std.mem.eql(u8, frame_id, "TIT1")) {
                title = try arena.dupe(u8, trim(content));
            } else if (std.mem.eql(u8, frame_id, "TPE2")) {
                artist = try arena.dupe(u8, trim(content));
            } else if (std.mem.eql(u8, frame_id, "TPE1")) {
                artist = try arena.dupe(u8, trim(content));
            } else if (std.mem.eql(u8, frame_id, "TALB")) {
                album = try arena.dupe(u8, trim(content));
            } else if (std.mem.eql(u8, frame_id, "TRCK")) {
                track_number = try arena.dupe(u8, trim(content));
            }
        }

        pos += 10 + frame_size;
    }

    // std.debug.print(" ID3 major version {d}\n", .{mp3[3]});
    // std.debug.print(" ID3 minor version {d}\n", .{mp3[4]});
    // std.debug.print("First track_number : {X}\n", .{track_number[0..4]});

    const output_len = 9 + title.len + artist.len + album.len + track_number.len;
    if (output_len == 9)  return null;

    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    _ = try std.fmt.bufPrint(output[0..], "{s} - {s} - {s} - {s}", .{title, album, track_number, artist});
    return output;
}

fn trim(input: []u8) []const u8 {
  return std.mem.trim(u8, input, &[_]u8{0});
}

fn indexOfText(input: []u8) usize {
    if (input[0] == 0x00 or 0x03 < input[0]) {
        return 0;
    } else if (input[0] == 0x01) {
        return 3;
    } else if (input[0] == 0x02 or input[0] == 0x03) {
        return 1;
    } else {
        unreachable;
    }
}

fn attemptId3v1(allocator: Allocator, io: std.Io, file: std.Io.File) !?[]u8 {
    const buffer = try allocator.alloc(u8, 128);
    defer allocator.free(buffer);

    const file_size: u64 = (try file.stat(io)).size;
    _ = try file.readPositionalAll(io, buffer, file_size - 128);

    if (!isTAG(buffer, 0)) {
        return null;
    }

    var title: []u8 = &.{};
    var artist: []u8 = &.{};
    var album: []u8 = &.{};
    var track_number: []u8 = &.{};

    var i: u8 = 3;

    while (buffer[i] != 0 and i < 33) {
        i += 1;
    }
    title = buffer[3..i];

    i = 33;
    while (buffer[i] != 0 and i < 63) {
        i += 1;
    }
    artist = buffer[33..i];

    i = 63;
    while (buffer[i] != 0 and i < 93) {
        i += 1;
    }
    album = buffer[63..i];

    if (buffer[125] == 0 and 0 < buffer[126]) {
        const max_len = 3;
        var buf: [max_len]u8 = undefined;
        track_number = try std.fmt.bufPrint(&buf, "{}", .{buffer[126]});
    }

    const output_len = 9 + title.len + artist.len + album.len + track_number.len;
    if (output_len == 9) {
        return null;
    }
    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    _ = try std.fmt.bufPrint(output[0..], "{s} - {s} - {s} - {s}", .{title, album, track_number, artist});
    return output;
}

fn printWhatOtherVersionsAreInTheFile(mp3: []const u8) void {
    if (isID3(mp3, 0)) {
        std.debug.print("has ID3v2 at start\n", .{});
        std.debug.print(" ID3 major version {d}\n", .{mp3[3]});
        std.debug.print(" ID3 minor version {d}\n", .{mp3[4]});
        const tagSize = getSynchsafeU32(mp3, 6);
        std.debug.print(" ID3 size {d}\n", .{tagSize});
    }
    if (hasID3v1(mp3)) {
        if (is3DI(mp3, mp3.len - 138))  {
            std.debug.print("has ID3v2 at end\n", .{});
        }
        std.debug.print("has ID3v1\n", .{});
    } else {
        if (is3DI(mp3, mp3.len - 10))  {
            std.debug.print("has ID3v2 at end\n", .{});
        }
    }
}

fn getSynchsafeU32(mp3: []const u8, i: usize) u32 {
    const alpha: u32 = @intCast(mp3[i]);
    const beta: u32 = @intCast(mp3[i+1]);
    const gamma: u32 = @intCast(mp3[i+2]);
    const delta: u32 = @intCast(mp3[i+3]);
    return (alpha << 21) | (beta << 14) | (gamma << 7) | delta;
}

fn isID3(mp3: []const u8, i: usize) bool {
    return std.mem.eql(u8, mp3[i..i+3], "ID3");
}

fn is3DI(mp3: []const u8, i: usize) bool {
    return (mp3[i] == '3' and mp3[i+1] == 'D' and mp3[i+2] == 'I');
}

fn isTAG(mp3: []const u8, i: usize) bool {
    return std.mem.eql(u8, mp3[i..i+3], "TAG");
}

fn hasID3v1(mp3: []const u8) bool {
    return isTAG(mp3, mp3.len - 128);
}
fn printID3v1(mp3: []const u8) void {
    var i: usize = mp3.len - 128;

    if (isTAG(mp3, i)) {
        std.debug.print("Found TAG at {d}\n", .{i});
        i += 128;
    } else {
        std.debug.print("Found no ID3v1 TAG at {d}\n", .{i});
        return;
    }
}


pub fn getIndexOfAudio(mp3: []u8)  usize {
    if (!isID3(mp3, 0) or mp3[3] != 3 ) {
        return 0;
    }

    const post_id3v2 = getSynchsafeU32(mp3, 6) + 10;

    if (post_id3v2 == 0xff) {
        return post_id3v2;
    } else {
        return 0;
    }
}
