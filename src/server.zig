//! Putting the socket binding and connection accepting behind simple method calls
const std = @import("std");
const scc = @import("protocol.zig");
const Allocator = std.mem.Allocator;
const posix = std.posix;

pub const Server = struct {
    allocator: Allocator,
    address: std.net.Address,
    listener: posix.socket_t,

    pub fn init(allocator: Allocator, name: []const u8, port: u16) !Server {
        const address = try std.net.Address.parseIp(name, port);
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);

        return Server{
            .allocator = allocator,
            .address = address,
            .listener = listener,
        };
    }

    pub fn listen(self: Server) !void {
        try posix.setsockopt(self.listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(self.listener, &self.address.any, self.address.getOsSockLen());
        try posix.listen(self.listener, 128);
        std.debug.print("Listening on port {}\n", .{self.address.getPort()});
    }

    pub fn accept(self: Server) !scc.Protocol {
        var client_address: std.net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(std.net.Address);
        const socket = try posix.accept(self.listener, &client_address.any, &client_address_len, 0);

        std.debug.print("{} connected\n", .{client_address});
        return scc.Protocol.init(self.allocator, socket);
    }

    pub fn destroy(self: Server) void {
        posix.close(self.listener);
    }
};
