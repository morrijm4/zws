const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zws = @import("zws");
const App = zws.App;
const Request = zws.Request;
const Response = zws.Response;

var i: u32 = 0;

fn counter(io: Io, gpa: Allocator, req: Request) anyerror!Response {
    _ = io;
    _ = req;
    i += 1;

    var res = try Response.init(gpa, .Ok);

    res.body = try std.fmt.allocPrint(gpa, "{d}", .{i});
    const len = try std.fmt.allocPrint(gpa, "{d}", .{res.body.len});
    try res.headers.put("Content-Type", "text/plain");
    try res.headers.put("Content-Length", len);

    return res;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const buf = try gpa.alloc(u8, 1024 * 1024 * 16); // 16 MB
    defer gpa.free(buf);

    var arena = std.heap.FixedBufferAllocator.init(buf);

    var app = try App.init(arena.allocator(), .{});

    var ctx: zws.static_assets.Context = .{
        .path = "/public",
        .io = io,
        .gpa = gpa,
    };
    try app.use(zws.static_assets.init(&ctx));
    try app.get("/counter", counter);

    try app.listen(io, "127.0.0.1:3000");
}
