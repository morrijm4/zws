const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const zws = @import("zws");
const App = zws.App;
const Request = zws.Request;
const Response = zws.Response;
const assets = zws.assets;
const logger = zws.logger;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const buf = try gpa.alloc(u8, 1024 * 1024 * 16); // 16 MB
    defer gpa.free(buf);

    var fba = FixedBufferAllocator.init(buf);
    const arena = fba.allocator();

    var app = App.init(.{});
    try app.use(arena, assets.init("/public"));
    try app.use(arena, logger.init());
    try app.listen(io, gpa, "127.0.0.1:3000");
}
