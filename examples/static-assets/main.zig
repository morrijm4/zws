const std = @import("std");
const Allocator = std.mem.Allocator;
const zws = @import("zws");

// Try these commands out!
//
// curl localhost:3000/hi
// curl localhost:3000/static/hi

pub fn main(init: std.process.Init) !void {
    var app = zws.App.init(.{});
    try app.use(init.gpa, zws.assets.init("./public"));
    try app.usePrefixed(init.gpa, "/static", zws.assets.init("./public"));
    try app.use(init.gpa, zws.logger.init());
    try app.listen(init.io, init.gpa, "127.0.0.1:3000");
}
