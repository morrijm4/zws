const std = @import("std");
const http = @import("http.zig");
const plugin = @import("plugins/plugin.zig");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const IpAddress = net.IpAddress;
const Stream = net.Stream;
const Request = http.Request;
const Response = http.Response;
const assert = std.debug.assert;

pub const App = @This();

opts: Options,
gpa: Allocator,
handlers: Handlers,
plugins: std.ArrayList(plugin.Interface),
worker_arenas: []FixedBufferAllocator,

const Options = struct {
    client_max_size_url: u32 = 1024 * 2,
    client_max_size_headers: u32 = 1024 * 8,
    client_max_size_body: u32 = 1024 * 1024,
    worker_arena_size: u32 = 1024 * 1024 * 2,
    workers: u32 = 1,
};

pub fn init(gpa: Allocator, opts: Options) Allocator.Error!App {
    const max_request_size =
        opts.client_max_size_url +
        opts.client_max_size_headers +
        opts.client_max_size_body;

    assert(opts.worker_arena_size >= max_request_size);

    const arenas = try gpa.alloc(FixedBufferAllocator, opts.workers);

    for (arenas) |*a| {
        const buf = try gpa.alloc(u8, opts.worker_arena_size);
        a.* = FixedBufferAllocator.init(buf);
    }

    return .{
        .opts = opts,
        .gpa = gpa,
        .plugins = .empty,
        .worker_arenas = arenas,
        .handlers = .init(gpa),
    };
}

pub fn deinit(app: *App) void {
    app.handlers.gets.deinit(app.gpa);
    app.handlers.heads.deinit(app.gpa);
    app.handlers.posts.deinit(app.gpa);
    app.handlers.puts.deinit(app.gpa);
    app.handlers.patchs.deinit(app.gpa);
    app.handlers.deletes.deinit(app.gpa);
    app.handlers.options.deinit(app.gpa);
    app.handlers.connects.deinit(app.gpa);
    app.plugins.deinit(app.gpa);

    for (app.worker_arenas) |arena| {
        app.gpa.free(arena.buffer);
    }
    app.gpa.free(app.worker_arenas);
}

const ListenError =
    IpAddress.ListenError ||
    IpAddress.ParseLiteralError ||
    net.Server.AcceptError;

pub fn listen(app: *App, io: Io, address: []const u8) ListenError!noreturn {
    const ip = try IpAddress.parseLiteral(address);
    var server = try ip.listen(io, .{ .reuse_address = true });

    var worker = Worker.init(&app.handlers, app.plugins.items, app.worker_arenas[0]);

    while (true) {
        const stream = try server.accept(io);
        worker.serve(io, stream, app.opts);
    }
}
const Worker = struct {
    arena: FixedBufferAllocator,
    plugins: []const plugin.Interface,
    handlers: *Handlers,

    fn init(
        handlers: *Handlers,
        plugins: []const plugin.Interface,
        arena: FixedBufferAllocator,
    ) Worker {
        return .{
            .arena = arena,
            .plugins = plugins,
            .handlers = handlers,
        };
    }

    fn serve(worker: *Worker, io: Io, stream: Stream, opts: Options) void {
        defer worker.arena.reset();
        defer stream.close(io);

        var req_buffer: [1024 * 4]u8 = undefined;
        var res_buffer: [1024 * 4]u8 = undefined;
        var stream_reader = stream.reader(io, &req_buffer);
        var stream_writer = stream.writer(io, &res_buffer);

        const reader = &stream_reader.interface;
        const writer = &stream_writer.interface;

        const gpa = worker.arena.allocator();

        const limits: Request.Limits = .{
            .max_size_url = opts.client_max_size_url,
            .max_size_headers = opts.client_max_size_headers,
            .max_size_body = opts.client_max_size_body,
        };

        var req = Request.parse(gpa, reader, limits) catch |err| {
            return worker.onError(err).send(writer);
        };

        for (worker.plugins) |plug| {
            if (plug.before) |callback| {
                callback(io, gpa, &req, plug.userdata) catch |err| {
                    return worker.onError(err).send(writer);
                };
            }
        }

        var res = worker.onRequest(io, req);

        for (worker.plugins) |plug| {
            if (plug.after) |callback| {
                callback(io, gpa, req, &res, plug.userdata) catch |err| {
                    return worker.onError(err).send(writer);
                };
            }
        }

        res.send(writer);
    }

    fn onRequest(worker: *Worker, io: Io, req: Request) Response {
        const handler = switch (req.method) {
            .GET => worker.handlers.gets.get(req.path.buf),
            .HEAD => worker.handlers.heads.get(req.path.buf),
            .POST => worker.handlers.posts.get(req.path.buf),
            .PUT => worker.handlers.puts.get(req.path.buf),
            .PATCH => worker.handlers.patchs.get(req.path.buf),
            .DELETE => worker.handlers.deletes.get(req.path.buf),
            .OPTIONS => worker.handlers.options.get(req.path.buf),
            .CONNECT => worker.handlers.connects.get(req.path.buf),
        };

        if (handler) |handle| {
            return handle(io, worker.arena.allocator(), req) catch |err| {
                return worker.onError(err);
            };
        }

        return worker.onError(http.Error.NotFound);
    }

    fn onError(worker: *Worker, err: anyerror) Response {
        const gpa = worker.arena.allocator();
        return Response.fromError(gpa, err);
    }
};

pub fn use(app: *App, plug: plugin.Interface) Allocator.Error!void {
    try app.plugins.append(app.gpa, plug);
}

pub fn get(
    app: *App,
    path: []const u8,
    handler: Handler,
) Allocator.Error!void {
    try app.handlers.gets.put(path, handler);
}

pub fn post(
    app: *App,
    path: []const u8,
    handler: Handler,
) Allocator.Error!void {
    try app.handlers.posts.put(path, handler);
}
pub fn put(
    app: *App,
    path: []const u8,
    handler: Handler,
) Allocator.Error!void {
    try app.handlers.puts.put(path, handler);
}

pub fn patch(
    app: *App,
    path: []const u8,
    handler: Handler,
) Allocator.Error!void {
    try app.handlers.patchs.put(path, handler);
}

pub fn delete(
    app: *App,
    path: []const u8,
    handler: Handler,
) Allocator.Error!void {
    try app.handlers.deletes.put(path, handler);
}

const Handler = *const fn (Io, Allocator, Request) anyerror!Response;

const Handlers = struct {
    gets: std.StringHashMap(Handler),
    heads: std.StringHashMap(Handler),
    posts: std.StringHashMap(Handler),
    puts: std.StringHashMap(Handler),
    patchs: std.StringHashMap(Handler),
    deletes: std.StringHashMap(Handler),
    options: std.StringHashMap(Handler),
    connects: std.StringHashMap(Handler),

    fn init(gpa: Allocator) Handlers {
        return .{
            .gets = .init(gpa),
            .heads = .init(gpa),
            .posts = .init(gpa),
            .puts = .init(gpa),
            .patchs = .init(gpa),
            .deletes = .init(gpa),
            .options = .init(gpa),
            .connects = .init(gpa),
        };
    }
};
