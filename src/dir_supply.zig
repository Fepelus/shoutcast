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
    config: cfg.Config,
    index: usize,

    pub fn init(allocator: Allocator, config: cfg.Config) DirectorySupply {
      return DirectorySupply{
          .allocator = allocator,
          .config = config,
          .index = 0, // of config.albums that should play _next_
        };
    }

    pub fn has_next(self: DirectorySupply) bool {
       return !self.config.inorder or self.index < self.config.albums.len;
    }

    pub fn next(self: *DirectorySupply) !dir.Directory {
        if (self.config.inorder) {
            self.index += 1;
            return try dir.Directory.init(self.allocator, self.config.albums[self.index - 1]);
        }

        const random_index = std.crypto.random.uintLessThan(usize, self.config.albums.len);
        return try dir.Directory.init(self.allocator, self.config.albums[random_index]);
    }

};
