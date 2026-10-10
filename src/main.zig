const std = @import("std");
const Io = std.Io;

const zws = @import("zws");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var server = try zws.init(gpa, .{ .address = "127.0.0.1:3000" });
    try server.start(io);
}
