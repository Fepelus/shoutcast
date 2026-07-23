//! Putting the socket binding and connection accepting behind simple method calls
const std = @import("std");
const scc = @import("protocol.zig");
const Allocator = std.mem.Allocator;
const net = std.Io.net;

pub const Server = struct {
    allocator: Allocator,
    io: std.Io,
    address: net.IpAddress,
    server: net.Server,

    pub fn init(allocator: Allocator, io: std.Io, name: []const u8, port: u16) !Server {
        const address = try net.IpAddress.parse(name, port);

        return Server{
            .allocator = allocator,
            .io = io,
            .address = address,
            .server = undefined,
        };
    }

    pub fn listen(self: *Server) !void {
        self.server = try self.address.listen(self.io, .{ .reuse_address = true });
        std.debug.print("Listening on port {}\n", .{self.address.getPort()});
    }

    pub fn accept(self: *Server) !scc.Protocol {
        const stream = try self.server.accept(self.io);
        return try scc.Protocol.init(self.allocator, self.io, stream);
    }

    pub fn close(self: *Server) void {
        self.server.deinit(self.io);
    }
};
