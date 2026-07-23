//! Choose the next album (that is, directory) to play, given the config.
//! If config.inorder then this server will play each album specified once
//! one after the other in order and then halt. If false then will play
//! forever, choosing the next album randomly from the list of albums.
const std = @import("std");
const cfg = @import("config.zig");
const dir = @import("directory.zig");
const Allocator = std.mem.Allocator;

pub const DirectorySupply = struct {
    allocator: Allocator,
    io: std.Io,
    config: cfg.Config,
    index: usize,

    pub fn init(allocator: Allocator, io: std.Io, config: cfg.Config) DirectorySupply {
      return DirectorySupply{
          .allocator = allocator,
          .io = io,
          .config = config,
          .index = 0,
        };
    }

    pub fn next(self: *DirectorySupply) !?dir.Directory {
        if (self.config.inorder) {
            if (self.config.albums.len <= self.index) return null; // Everything has played once.
            self.index += 1;
            return try dir.Directory.init(self.allocator, self.io, self.config.albums[self.index - 1]);
        }

        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            self.io.random(std.mem.asBytes(&seed));
            break :blk seed;
        });
        const rand = prng.random();

        const albumsCount = self.config.albums.len;
        // std.debug.assert(0 < albumsCount); there is nothing in code ensuring this.
        // Currently the code will crash if you do not specify at least one album in config
        const random_index = rand.uintLessThan(usize, albumsCount);
        return try dir.Directory.init(self.allocator, self.io, self.config.albums[random_index]);
    }

};
