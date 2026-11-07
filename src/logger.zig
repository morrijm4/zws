const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const Controller = @import("Controller.zig");

const Worker = @import("Worker.zig");
const Context = Worker.Context;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

fn log(
    req: *Request,
    res: *Response,
    ctx: *Context,
) anyerror!void {
    std.log.info("{d} {s} {s} RSS {d} Worker {d}", .{
        @intFromEnum(res.code),
        @tagName(req.method),
        req.path.buf,
        ctx.arena.end_index,
        ctx.worker_id,
    });
}

pub fn init() Controller.Interface {
    return .{
        .on_request = &log,
        .on_error = &log,
        .userdata = &.{},
    };
}
