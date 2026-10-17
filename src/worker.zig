const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Stream = Io.net.Stream;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const assert = std.debug.assert;

const app = @import("app.zig");
const Options = app.Options;

const Handlers = @import("handler.zig");
const Handler = Handlers.Handler;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

pub const Worker = @This();

ctx: Context,
handlers: *Handlers,
opts: Options,

pub const Context = struct {
    io: Io,
    arena: FixedBufferAllocator,
    worker_idx: u32,
    handler: *Handler,

    pub fn init(io: Io, buf: []u8) Context {
        return .{
            .io = io,
            .arena = FixedBufferAllocator.init(buf),
            .worker_idx = 0,
            .handler = undefined,
        };
    }

    pub fn getUserData(ctx: *Context, U: type) *U {
        return ctx.handler.getUserData(U);
    }
};

pub fn init(
    ctx: Context,
    handlers: *Handlers,
    opts: Options,
) Worker {
    return .{
        .ctx = ctx,
        .handlers = handlers,
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

    const pipeline = self.buildPipeline(&req) catch |err| {
        return self.onError(err, &req, &res).send(writer);
    };

    for (pipeline) |*handler| {
        const on_request = switch (handler.kind) {
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
            self.ctx.handler = handler;
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
    const pipeline = self.buildPipeline(req) catch @panic("OOM onError");

    for (pipeline) |*handler| {
        const on_error = switch (handler.kind) {
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

fn buildPipeline(self: *Worker, req: *Request) Allocator.Error![]Handler {
    const gpa = self.ctx.arena.allocator();

    var handlers = try self.handlers.global.clone(gpa);

    for (self.handlers.prefixed.items) |handler| {
        switch (handler.kind) {
            .prefixed => |h| {
                if (std.mem.startsWith(u8, req.path.buf, h.prefix)) {
                    try handlers.append(gpa, handler);
                }
            },
            else => unreachable,
        }
    }

    const maybe_handler = switch (req.method) {
        .GET => self.handlers.gets.get(req.path.buf),
        .HEAD => self.handlers.heads.get(req.path.buf),
        .POST => self.handlers.posts.get(req.path.buf),
        .PUT => self.handlers.puts.get(req.path.buf),
        .PATCH => self.handlers.patchs.get(req.path.buf),
        .DELETE => self.handlers.deletes.get(req.path.buf),
        .OPTIONS => self.handlers.options.get(req.path.buf),
        .CONNECT => self.handlers.connects.get(req.path.buf),
    };

    if (maybe_handler) |handler| {
        try handlers.append(gpa, handler);
    }

    std.mem.sort(Handler, handlers.items, {}, Handler.lessThan);
    return handlers.items;
}
