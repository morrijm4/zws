const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

const work = @import("worker.zig");
const Context = work.Context;

pub const Controller = @This();

priority: u32,
kind: Kind,

pub const Kind = union(enum) {
    global: Global,
    prefixed: Prefixed,
    get: Exact,
    head: Exact,
    post: Exact,
    put: Exact,
    patch: Exact,
    delete: Exact,
    option: Exact,
    connect: Exact,
};

pub const Interface = struct {
    on_request: ?Callback = null,
    on_error: ?Callback = null,
    userdata: *anyopaque,
};

pub const Global = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
};

pub const Prefixed = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
    prefix: []const u8,
};

pub const Exact = struct {
    on_request: ?Callback,
    on_error: ?Callback,
    userdata: *anyopaque,
    path: []const u8,
};

pub const Callback = *const fn (
    *Request,
    *Response,
    *Context,
) anyerror!void;

pub fn getUserData(self: *Controller, U: type) *U {
    const userdata = switch (self.kind) {
        .global => |h| h.userdata,
        .prefixed => |h| h.userdata,
        .get,
        .head,
        .post,
        .put,
        .patch,
        .delete,
        .connect,
        .option,
        => |h| h.userdata,
    };

    return @ptrCast(@alignCast(userdata));
}

pub fn lessThan(_: void, a: Controller, b: Controller) bool {
    return a.priority < b.priority;
}
