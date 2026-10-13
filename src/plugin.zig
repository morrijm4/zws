const std = @import("std");
const http = @import("http.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Request = http.Request;
const Response = http.Response;

pub const Plugin = struct {
    ctx: *anyopaque,
    before: ?Before,
    after: ?After,
};

const Before = *const fn (*Request, *anyopaque) anyerror!void;
const After = *const fn (Request, *Response, *anyopaque) anyerror!void;
