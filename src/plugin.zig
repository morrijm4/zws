const std = @import("std");
const http = @import("http.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Request = http.Request;
const Response = http.Response;

pub const Plugin = struct {
    ctx: *anyopaque,
    before: ?*const fn (*Request, *anyopaque) anyerror!void,
    after: ?*const fn (Request, *Response, *anyopaque) anyerror!void,
};
