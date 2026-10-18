const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Stream = Io.net.Stream;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const assert = std.debug.assert;

const app = @import("app.zig");
const Options = app.Options;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

const Controller = @import("controller.zig");
const Pipeline = @import("pipeline.zig");

pub const Worker = @This();

ctx: Context,
pipeline: *Pipeline,
opts: Options,

pub const Context = struct {
    io: Io,
    arena: FixedBufferAllocator,
    worker_idx: u32,
    controller: *Controller,

    pub fn init(io: Io, buf: []u8) Context {
        return .{
            .io = io,
            .arena = FixedBufferAllocator.init(buf),
            .worker_idx = 0,
            .controller = undefined,
        };
    }

    pub fn getUserData(ctx: *Context, U: type) *U {
        return ctx.controller.getUserData(U);
    }
};

pub fn init(
    ctx: Context,
    pipeline: *Pipeline,
    opts: Options,
) Worker {
    return .{
        .ctx = ctx,
        .pipeline = pipeline,
        .opts = opts,
    };
}

pub fn serve(self: *Worker, io: Io, stream: Stream) void {
    defer self.ctx.arena.reset();
    defer stream.close(io);

    var req_buffer: [1024 * 4]u8 = undefined;
    var res_buffer: [1024 * 4]u8 = undefined;
    var stream_reader = stream.reader(io, &req_buffer);
    var stream_writer = stream.writer(io, &res_buffer);

    const reader = &stream_reader.interface;
    const writer = &stream_writer.interface;

    const gpa = self.ctx.arena.allocator();

    const limits: Request.Limits = .{
        .max_size_url = self.opts.client_max_size_url,
        .max_size_headers = self.opts.client_max_size_headers,
        .max_size_body = self.opts.client_max_size_body,
    };

    var req = Request.parse(gpa, reader, limits) catch |err| {
        self.ctx.arena.reset();
        return Response.fromError(gpa, err).send(writer);
    };

    var res = Response.init(gpa, .NotFound) catch |err| {
        self.ctx.arena.reset();
        return Response.fromError(gpa, err).send(writer);
    };

    const pipeline = self.pipeline.build(gpa, &req) catch |err| {
        return self.onError(err, &req, &res).send(writer);
    };

    for (pipeline) |*controller| {
        const on_request = switch (controller.kind) {
            .global => |*h| h.on_request,
            .prefixed => |*h| h.on_request,
            .get,
            .head,
            .post,
            .put,
            .patch,
            .delete,
            .option,
            .connect,
            => |*h| h.on_request,
        };

        if (on_request) |func| {
            self.ctx.controller = controller;
            func(&req, &res, &self.ctx) catch |err| {
                return self.onError(err, &req, &res).send(writer);
            };
        }
    }

    res.send(writer);
}

fn onError(self: *Worker, err: anyerror, req: *Request, res: *Response) Response {
    self.ctx.arena.reset();
    const gpa = self.ctx.arena.allocator();
    const pipeline = self.pipeline.build(gpa, req) catch @panic("OOM onError");

    for (pipeline) |*controller| {
        const on_error = switch (controller.kind) {
            .global => |*h| h.on_error,
            .prefixed => |*h| h.on_error,
            .get => |*h| h.on_error,
            .head => |*h| h.on_error,
            .post => |*h| h.on_error,
            .put => |*h| h.on_error,
            .patch => |*h| h.on_error,
            .delete => |*h| h.on_error,
            .option => |*h| h.on_error,
            .connect => |*h| h.on_error,
        };

        if (on_error) |func| func(req, res, &self.ctx) catch @panic("TODO");
    }

    return Response.fromError(gpa, err);
}
