const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zws = @import("zws");

fn handleIndex(io: Io, gpa: Allocator, req: zws.Request) Allocator.Error!zws.Response {
    _ = io;
    _ = req;
    return zws.Response.init(gpa, .OK);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var app = try zws.init(gpa);
    try app.use(zws.static_assets.init());
    try app.get("/", handleIndex);
    try app.listen(io, "127.0.0.1:3000");
}
