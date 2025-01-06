//! Parse the ID3 tags of an MP3 file in order to format a trackinfo
//! string that goes into the metadata of the shoutcast stream.
//! It currently handles ID3v2.3, then tries ID3v2.4 and then falls
//! back to ID3v1
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn get_trackinfo(allocator: Allocator, mp3: []u8) ![]u8 {

    if (try attempt_id3v23(allocator, mp3)) |found_id3v23| {
        // std.debug.print("ID3v23\n",.{});
        return found_id3v23;
    }

    if (try attempt_id3v24(allocator, mp3)) |found_id3v24| {
        // std.debug.print("ID3v24\n",.{});
        return found_id3v24;
    }

    if (try attempt_id3v1(allocator, mp3)) |found_id3v1| {
        // std.debug.print("ID3v1\n",.{});
        return found_id3v1;
    }

    std.debug.print("No ID3 found\n",.{});
    print_what_other_versions_are_in_the_file(mp3);
    return &.{};
}

fn attempt_id3v23(allocator: Allocator, mp3: []u8) !?[]u8 {
    if (!is_ID3(mp3, 0) or  mp3[3] != 3) {
        return null;
    }

    var title: []u8 = &.{};
    var artist: []u8 = &.{};
    var album: []u8 = &.{};
    var track_number: []u8 = &.{};

   // const tagSize = get_synchsafe_u32(mp3, 6);

    var i: u32 = 10;
    while (is_id3v2frameId(mp3, i)) {
        const size  = get_synchsafe_u32(mp3, i+4);
        if (std.mem.eql(u8, mp3[i..i+4], "TIT2")) {
            const title_start = index_of_text(mp3[i..]);
            title =  mp3[i + title_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TIT1")) {
            const title_start = index_of_text(mp3[i..]);
            title =  mp3[i + title_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TPE1")) {
            const artist_start = index_of_text(mp3[i..]);
            artist =  mp3[i + artist_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TALB")) {
            const album_start = index_of_text(mp3[i..]);
            album =  mp3[i + album_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TRCK")) {
            const track_start = index_of_text(mp3[i..]);
            track_number = mp3[i+track_start..i+10+size];
        }

        i += 10 + size;
    }

    // std.debug.print(" ID3 major version {d}\n", .{mp3[3]});
    // std.debug.print(" ID3 minor version {d}\n", .{mp3[4]});
    // std.debug.print("First track_number : {X}\n", .{track_number[0..4]});

    const output_len = 9 + title.len + artist.len + album.len + track_number.len;
    if (output_len == 9) {
        return null;
    }
    const output = try allocator.alloc(u8, output_len);
    _ = try std.fmt.bufPrint(output[0..], "{s} - {s} - {s} - {s}", .{title, album, track_number, artist});
    // std.debug.print("output: {s}\n", .{output});
    return output;
}

fn attempt_id3v24(allocator: Allocator, mp3: []u8) !?[]u8 {
    if (!is_ID3(mp3, 0) or mp3[3] != 4) {
        return null;
    }

    var title: []u8 = &.{};
    var artist: []u8 = &.{};
    var album: []u8 = &.{};
    var track_number: []u8 = &.{};

    var i: u32 = 10;

    const flags = mp3[6];
    const EXTENDED_HEADER: u8 = 0x20;
    const has_extended_header: bool = 0 < (flags & EXTENDED_HEADER);
    if (has_extended_header) {
        const extended_header_size = get_synchsafe_u32(mp3, 10);
        i += extended_header_size;
    }


    // std.debug.print("[{d}] frame: {s}\n", .{i, mp3[i..i+4]});
    while (is_id3v2frameId(mp3, i)) {
        const size  = get_synchsafe_u32(mp3, i+4);
        // std.debug.print("framesize: {d}\n", .{size});
        // std.debug.print("flags: x{X}x{X}\n", .{mp3[i+8],mp3[i+9]});
        // const body_index = index_of_text(mp3[i..]);
        // std.debug.print("body: {s}\n", .{mp3[i+body_index..i+10+size]});
        if (std.mem.eql(u8, mp3[i..i+4], "TIT2")) {
            const title_start = index_of_text(mp3[i..]);
            title =  mp3[i + title_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TIT1")) {
            const title_start = index_of_text(mp3[i..]);
            title =  mp3[i + title_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TPE1")) {
            const artist_start = index_of_text(mp3[i..]);
            artist =  mp3[i + artist_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TALB")) {
            const album_start = index_of_text(mp3[i..]);
            album =  mp3[i + album_start..i+10+size];
        }
        if (std.mem.eql(u8, mp3[i..i+4], "TRCK")) {
            const track_start = index_of_text(mp3[i..]);
            track_number = mp3[i+track_start..i+10+size];
        }

        i += 10 + size;
        // std.debug.print("[{d}] frame: {s}\n", .{i, mp3[i..i+4]});

    }

    // std.debug.print(" ID3 major version {d}\n", .{mp3[3]});
    // std.debug.print(" ID3 minor version {d}\n", .{mp3[4]});

    // const robotRock = "Daft Punk - Alive 2007 - 01 - Robot Rock";
    // const new_string = try allocator.alloc(u8, robotRock.len);
    // @memcpy(new_string[0..robotRock.len], robotRock);
    // return new_string;

    const output_len = 9 + title.len + artist.len + album.len + track_number.len;
    if (output_len == 9) {
        return null;
    }
    const output = try allocator.alloc(u8, output_len);
    _ = try std.fmt.bufPrint(output[0..], "{s} - {s} - {s} - {s}", .{title, album, track_number, artist});
    return output;
}

// Skip unicode indicators if there are any
fn index_of_text(input: []u8) usize {
    if (0x04 < input[10]) {
        return 10;
    } else if (input[10] == 0x01) {
        return 13;
    } else {
        return 11;
    }

}

fn attempt_id3v1(allocator: Allocator, mp3: []u8) !?[]u8 {
    if (!has_id3v1(mp3)) {
        return null;
    }

    var title: []u8 = &.{};
    var artist: []u8 = &.{};
    var album: []u8 = &.{};
    var track_number: []u8 = &.{};
    const tag_start = mp3.len - 128;

    var i = tag_start + 3;
    while (mp3[i] != 0 and i < tag_start + 33) {
        i += 1;
    }
    title = mp3[tag_start + 3..i];

    i = tag_start + 33;
    while (mp3[i] != 0 and i < tag_start + 63) {
        i += 1;
    }
    artist = mp3[tag_start + 33..i];

    i = tag_start + 63;
    while (mp3[i] != 0 and i < tag_start + 93) {
        i += 1;
    }
    album = mp3[tag_start + 63..i];

    if (mp3[tag_start + 125] == 0 and 0 < mp3[tag_start + 126]) {
        const max_len = 3;
        var buf: [max_len]u8 = undefined;
        track_number = try std.fmt.bufPrint(&buf, "{}", .{mp3[tag_start + 126]});
    }

    const output_len = 9 + title.len + artist.len + album.len + track_number.len;
    if (output_len == 9) {
        return null;
    }
    const output = try allocator.alloc(u8, output_len);
    _ = try std.fmt.bufPrint(output[0..], "{s} - {s} - {s} - {s}", .{title, album, track_number, artist});
    return output;
}

fn print_what_other_versions_are_in_the_file(mp3: []const u8) void {
    if (is_ID3(mp3, 0)) {
        std.debug.print("has ID3v2 at start\n", .{});
        std.debug.print(" ID3 major version {d}\n", .{mp3[3]});
        std.debug.print(" ID3 minor version {d}\n", .{mp3[4]});
        const tagSize = get_synchsafe_u32(mp3, 6);
        std.debug.print(" ID3 size {d}\n", .{tagSize});
    }
    if (has_id3v1(mp3)) {
        if (is_3DI(mp3, mp3.len - 138))  {
            std.debug.print("has ID3v2 at end\n", .{});
        }
        std.debug.print("has ID3v1\n", .{});
    } else {
        if (is_3DI(mp3, mp3.len - 10))  {
            std.debug.print("has ID3v2 at end\n", .{});
        }
    }
}


// accepts those in id3v2.3 or id3v2.4
fn is_id3v2frameId(mp3: []const u8, i: usize) bool {
    // AENC|APIC|COMM|COMR
    if (mp3[i] == 'A') {
      if (mp3[i+1] == 'E') {
        return mp3[i+2] == 'N' and mp3[i+3] == 'C';
      }
      if (mp3[i+1] == 'P') {
        return mp3[i+2] == 'I' and mp3[i+3] == 'C';
      }
      if (mp3[i+1] == 'S') {
        return mp3[i+2] == 'P' and mp3[i+3] == 'I';
      }
      return false;
    }
    if (mp3[i] == 'C') {
      if (mp3[i+1] == 'O') {
        if (mp3[i+2] == 'M') {
          return mp3[i+3] == 'M' or mp3[i+3] == 'R';
        }
      }
      return false;
    }

    // |ENCR|EQUA|ETCO
    if (mp3[i] == 'E') {
      if (mp3[i+1] == 'N') {
        return mp3[i+2] == 'C' and mp3[i+3] == 'R';
      }
      if (mp3[i+1] == 'Q') {
          return mp3[i+2] == 'U' and (mp3[i+3] == 'A' or mp3[i+3] == '2');
      }
      if (mp3[i+1] == 'T') {
        return mp3[i+2] == 'C' and mp3[i+3] == 'O';
      }
      return false;
    }

    // |GEOB|GRID|IPLS|LINK
    if (mp3[i] == 'G') {
      if (mp3[i+1] == 'E') {
        return mp3[i+2] == 'O' and mp3[i+3] == 'B';
      }
      if (mp3[i+1] == 'R') {
        return mp3[i+2] == 'I' and mp3[i+3] == 'D';
      }
      return false;
    }
    if (mp3[i] == 'I') {
      return mp3[i+1] == 'P' and mp3[i+2] == 'L' and mp3[i+3] == 'S';
    }
    if (mp3[i] == 'L') {
      return mp3[i+1] == 'I' and mp3[i+2] == 'N' and mp3[i+3] == 'K';
    }

    // |MCDI|MLLT|OWNE
    if (mp3[i] == 'M') {
      if (mp3[i+1] == 'C') {
        return mp3[i+2] == 'D' and mp3[i+3] == 'I';
      }
      if (mp3[i+1] == 'L') {
        return mp3[i+2] == 'L' and mp3[i+3] == 'T';
      }
      return false;
    }
    if (mp3[i] == 'O') {
      return mp3[i+1] == 'W' and mp3[i+2] == 'N' and mp3[i+3] == 'E';
    }

    // |PRIV|PCNT|POPM|POSS
    if (mp3[i] == 'P') {
      if (mp3[i+1] == 'P') {
        return mp3[i+2] == 'I' and mp3[i+3] == 'V';
      }
      if (mp3[i+1] == 'C') {
        return mp3[i+2] == 'N' and mp3[i+3] == 'T';
      }
      if (mp3[i+1] == 'O') {
        return (mp3[i+2] == 'P' and mp3[i+3] == 'M')
            or (mp3[i+2] == 'O' and mp3[i+3] == 'S');
      }
      return false;
    }

    // |RBUF|RVAD|RVRB
    if (mp3[i] == 'R') {
      if (mp3[i+1] == 'B') {
        return mp3[i+2] == 'U' and mp3[i+3] == 'F';
      }
      if (mp3[i+1] == 'V') {
        return (mp3[i+2] == 'A' and (mp3[i+3] == 'D' or mp3[i+3] == '2'))
            or (mp3[i+2] == 'R' and mp3[i+3] == 'B');
      }
      return false;
    }

    // |SYLT|SYTC
    if (mp3[i] == 'S') {
        if (mp3[i+1] == 'E') {
          return mp3[i+2] == 'E' and mp3[i+3] == 'K';
        }
        if (mp3[i+1] == 'I') {
          return mp3[i+2] == 'G' and mp3[i+3] == 'N';
        }
      if (mp3[i+1] == 'Y') {
        return (mp3[i+2] == 'L' and mp3[i+3] == 'T')
            or (mp3[i+2] == 'T' and mp3[i+3] == 'C');
      }
      return false;
    }

    if (mp3[i] == 'T') {
      // |TALB|TBPM|TCOM|TCON|TCOP|TDAT|TDLY|TENC|TEXT|TFLT|TIME|TIT1|TIT2|TIT3|TKEY|TLAN|TLEN|TMED
      if (mp3[i+1] == 'A') {
        return mp3[i+2] == 'L' and mp3[i+3] == 'B';
      }
      if (mp3[i+1] == 'B') {
        return mp3[i+2] == 'P' and mp3[i+3] == 'M';
      }
      if (mp3[i+1] == 'C') {
          if (mp3[i+2] == 'O') {
              return mp3[i+3] == 'M' or mp3[i+3] == 'N' or mp3[i+3] == 'P';
          }
          return false;
      }
      if (mp3[i+1] == 'D') {
        return (mp3[i+2] == 'A' and mp3[i+3] == 'T')
            or (mp3[i+2] == 'E' and mp3[i+3] == 'N')
            or (mp3[i+2] == 'L' and mp3[i+3] == 'Y')
            or (mp3[i+2] == 'O' and mp3[i+3] == 'R')
            or (mp3[i+2] == 'R' and (mp3[i+3] == 'C' or mp3[i+3] == 'L'))
            or (mp3[i+2] == 'T' and mp3[i+3] == 'G');
      }
      if (mp3[i+1] == 'E') {
        return (mp3[i+2] == 'N' and mp3[i+3] == 'C')
            or (mp3[i+2] == 'X' and mp3[i+3] == 'T');
      }
      if (mp3[i+1] == 'F') {
        return mp3[i+2] == 'L' and mp3[i+3] == 'T';
      }
      if (mp3[i+1] == 'I') {
          if (mp3[i+2] == 'M') {
              return mp3[i+3] == 'E';
          }
          if (mp3[i+2] == 'P') {
              return mp3[i+3] == 'L';
          }
          if (mp3[i+2] == 'T') {
              return mp3[i+3] == '1' or mp3[i+3] == '2' or mp3[i+3] == '3';
          }
          return false;
      }
      if (mp3[i+1] == 'K') {
        return mp3[i+2] == 'E' and mp3[i+3] == 'Y';
      }
      if (mp3[i+1] == 'L' and mp3[i+3] == 'N') {
        return mp3[i+2] == 'A' and mp3[i+2] == 'E';
      }
      if (mp3[i+1] == 'M') {
        return (mp3[i+2] == 'E' and mp3[i+3] == 'D')
            or (mp3[i+2] == 'O' and mp3[i+3] == 'O');
      }

      // |TOAL|TOFN|TOLY|TOPE|TORY|TOWN|TPE1|TPE2|TPE3|TPE4|TPOS|TPUB|TRCK|TRDA|TRSN|TRSO|TSIZ|TSRC|TSSE|TYER|TXXX
      if (mp3[i+1] == 'O') {
          if (mp3[i+2] == 'A') {
              return mp3[i+3] == 'L';
          }
          if (mp3[i+2] == 'F') {
              return mp3[i+3] == 'N';
          }
          if (mp3[i+2] == 'L') {
              return mp3[i+3] == 'Y';
          }
          if (mp3[i+2] == 'P') {
              return mp3[i+3] == 'E';
          }
          if (mp3[i+2] == 'R') {
              return mp3[i+3] == 'Y';
          }
          if (mp3[i+2] == 'W') {
              return mp3[i+3] == 'N';
          }
          return false;
      }
      if (mp3[i+1] == 'P') {
          if (mp3[i+2] == 'E') {
              return mp3[i+3] == '1' or mp3[i+3] == '2' or mp3[i+3] == '3' or mp3[i+3] == '4';
          }
          if (mp3[i+2] == 'O') {
              return mp3[i+3] == 'S';
          }
          if (mp3[i+2] == 'R') {
              return mp3[i+3] == 'O';
          }
          if (mp3[i+2] == 'U') {
              return mp3[i+3] == 'B';
          }
      }
      if (mp3[i+1] == 'R') {
          if (mp3[i+2] == 'C') {
              return mp3[i+3] == 'K';
          }
          if (mp3[i+2] == 'D') {
              return mp3[i+3] == 'A';
          }
          if (mp3[i+2] == 'S') {
              return mp3[i+3] == 'N' or mp3[i+3] == 'O';
          }
          return false;
      }
      if (mp3[i+1] == 'S') {
          return (mp3[i+2] == 'I' and mp3[i+3] == 'Z')
              or (mp3[i+2] == 'O' and (mp3[i+3] == 'A' or mp3[i+3] == 'P' or mp3[i+3] == 'T'))
              or (mp3[i+2] == 'R' and mp3[i+3] == 'C')
              or (mp3[i+2] == 'S' and (mp3[i+3] == 'E' or mp3[i+3] == 'T'));
      }
        if (mp3[i+1] == 'Y') {
            return mp3[i+2] == 'E' and mp3[i+3] == 'R';
        }
        if (mp3[i+1] == 'X') {
            return mp3[i+2] == 'X' and mp3[i+3] == 'X';
        }
        return false;
    }

    // |UFID|USER|USLT
    if (mp3[i] == 'U') {
        if (mp3[i+1] == 'F') {
            return mp3[i+2] == 'I' and mp3[i+3] == 'D';
        }
        if (mp3[i+1] == 'S') {
            return (mp3[i+2] == 'E' and mp3[i+3] == 'R')
                or (mp3[i+2] == 'L' and mp3[i+3] == 'T');
        }
        return false;
    }

    // |WCOM|WCOP|WOAF|WOAR|WOAS|WORS|WPAY|WPUB|WXXX',
    if (mp3[i] == 'W') {
        if (mp3[i+1] == 'C' and mp3[i+2] == 'O') {
            return mp3[i+3] == 'M' and mp3[i+3] == 'P';
        }
        if (mp3[i+1] == 'O') {
            if (mp3[i+2] == 'A') {
                return mp3[i+3] == 'F' or mp3[i+3] == 'R' or mp3[i+3] == 'S';
            }
            if (mp3[i+2] == 'R') {
                return mp3[i+3] == 'S';
            }
            return false;
        }
        if (mp3[i+1] == 'P') {
            return (mp3[i+2] == 'A' and mp3[i+3] == 'Y')
                or (mp3[i+2] == 'U' and mp3[i+3] == 'P');
        }
        return mp3[i+1] == 'X' and mp3[i+2] == 'X' and mp3[i+3] == 'X';
    }

    return false;
}

fn get_synchsafe_u32(mp3: []const u8, i: usize) u32 {
    const alpha: u32 = @intCast(mp3[i]);
    const beta: u32 = @intCast(mp3[i+1]);
    const gamma: u32 = @intCast(mp3[i+2]);
    const delta: u32 = @intCast(mp3[i+3]);
    return (alpha << 21) | (beta << 14) | (gamma << 7) | delta;
}

fn is_ID3(mp3: []const u8, i: usize) bool {
    return (mp3[i] == 'I' and mp3[i+1] == 'D' and mp3[i+2] == '3');
}

fn is_3DI(mp3: []const u8, i: usize) bool {
    return (mp3[i] == '3' and mp3[i+1] == 'D' and mp3[i+2] == 'I');
}

fn at_mpeg_ones(mp3: []const u8, i: usize) bool {
    return mp3[i] == 0xFF and (mp3[i+1] & 0xC0) == 0xC0;
}

fn is_TAG(mp3: []const u8, i: usize) bool {
    return (mp3[i] == 'T' and mp3[i+1] == 'A' and mp3[i+2] == 'G');
}

fn has_id3v1(mp3: []const u8) bool {
    return is_TAG(mp3, mp3.len - 128);
}
fn print_id3v1(mp3: []const u8) void {
    var i: usize = mp3.len - 128;

    if (is_TAG(mp3, i)) {
        std.debug.print("Found TAG at {d}\n", .{i});
        i += 128;
    } else {
        std.debug.print("Found no ID3v1 TAG at {d}\n", .{i});
        return;
    }
}


pub fn get_index_of_audio(mp3: []u8)  usize {
    if (!is_ID3(mp3, 0) or mp3[3] != 3 ) {
        return 0;
    }

    const post_id3v2 = get_synchsafe_u32(mp3, 6) + 10;

    if (post_id3v2 == 0xff) {
        return post_id3v2;
    } else {
        return 0;
    }
}
