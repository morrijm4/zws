const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const Controller = @import("controller.zig");

const work = @import("worker.zig");
const Worker = work.Worker;
const Context = Worker.Context;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

fn log(
    req: *Request,
    res: *Response,
    ctx: *Context,
) anyerror!void {
    const gpa = ctx.arena.allocator();
    const buf = try gpa.alloc(u8, 4096);
    defer gpa.free(buf);

    const stdout = Io.File.stdout();
    var stdout_writer = stdout.writer(ctx.io, buf);
    const w = &stdout_writer.interface;

    try w.print("{d} {s} {s} RSS {d} Worker {d}\n", .{
        @intFromEnum(res.code),
        @tagName(req.method),
        req.path.buf,
        ctx.arena.end_index,
        ctx.worker_idx,
    });
    try w.flush();
}

pub fn init() Controller.Interface {
    return .{
        .on_request = &log,
        .on_error = &log,
        .userdata = &.{},
    };
}
