const std = @import("std");
const plug = @import("plugin.zig");
const http = @import("http.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Request = http.Request;
const Response = http.Response;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
};

fn after(req: Request, res: *Response, ctx: *anyopaque) anyerror!void {
    _ = req;
    _ = res;
    _ = ctx;
}

pub fn init() plug.Plugin {
    return .{
        .ctx = &.{},
        .before = null,
        .after = &after,
    };
}
