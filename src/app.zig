const std = @import("std");
const http = @import("http.zig");
const plug = @import("plugin.zig");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;
const IpAddress = net.IpAddress;
const Stream = net.Stream;
const Plugin = plug.Plugin;
const Request = http.Request;
const Response = http.Response;

const static = @import("static_assets.zig");

pub const App = @This();

gpa: Allocator,
worker: Worker,

pub fn init(gpa: Allocator) Allocator.Error!App {
    return .{
        .gpa = gpa,
        .worker = try .init(gpa, 1024 * 16), // 16 KB
    };
}

const ListenError =
    IpAddress.ListenError ||
    IpAddress.ParseLiteralError ||
    net.Server.AcceptError;

pub fn listen(app: *App, io: Io, address: []const u8) ListenError!noreturn {
    const ip = try IpAddress.parseLiteral(address);
    var server = try ip.listen(io, .{ .reuse_address = true });

    while (true) {
        const stream = try server.accept(io);
        app.worker.serve(io, stream);
    }
}

pub fn use(app: *App, plugin: Plugin) Allocator.Error!void {
    try app.worker.plugins.append(app.gpa, plugin);
}

pub fn get(app: *App, path: []const u8, handler: Handler) Worker.AddRouteError!void {
    try app.worker.addRoute(.GET, path, handler);
}

pub fn post(app: *App, path: []const u8, handler: Handler) Worker.AddRouteError!void {
    try app.worker.addRoute(.POST, path, handler);
}
pub fn put(app: *App, path: []const u8, handler: Handler) Worker.AddRouteError!void {
    try app.worker.addRoute(.PUT, path, handler);
}

pub fn patch(app: *App, path: []const u8, handler: Handler) Worker.AddRouteError!void {
    try app.worker.addRoute(.PATCH, path, handler);
}

pub fn delete(app: *App, path: []const u8, handler: Handler) Worker.AddRouteError!void {
    try app.worker.addRoute(.DELETE, path, handler);
}

const Handler = *const fn (Io, Allocator, Request) anyerror!Response;

const Worker = struct {
    arena: std.heap.FixedBufferAllocator,

    gets: std.StringHashMap(Handler),
    heads: std.StringHashMap(Handler),
    posts: std.StringHashMap(Handler),
    puts: std.StringHashMap(Handler),
    patchs: std.StringHashMap(Handler),
    deletes: std.StringHashMap(Handler),
    options: std.StringHashMap(Handler),
    connects: std.StringHashMap(Handler),

    plugins: std.ArrayList(plug.Plugin),

    fn init(gpa: Allocator, buffer_size: u32) Allocator.Error!Worker {
        const buffer = try gpa.alloc(u8, buffer_size);
        return .{
            .arena = .init(buffer),

            .gets = .init(gpa),
            .heads = .init(gpa),
            .posts = .init(gpa),
            .puts = .init(gpa),
            .patchs = .init(gpa),
            .deletes = .init(gpa),
            .options = .init(gpa),
            .connects = .init(gpa),

            .plugins = .empty,
        };
    }

    fn deinit(worker: *Worker, gpa: Allocator) void {
        gpa.free(worker.arena.buffer);
        worker.gets.deinit();
        worker.heads.deinit(gpa);
        worker.posts.deinit(gpa);
        worker.puts.deinit(gpa);
        worker.patchs.deinit(gpa);
        worker.deletes.deinit(gpa);
        worker.options.deinit(gpa);
        worker.connects.deinit(gpa);
    }

    const AddRouteError = Allocator.Error;

    fn addRoute(
        worker: *Worker,
        method: http.Method,
        path: []const u8,
        handler: Handler,
    ) AddRouteError!void {
        try switch (method) {
            .GET => worker.gets.put(path, handler),
            .HEAD => worker.heads.put(path, handler),
            .POST => worker.posts.put(path, handler),
            .PUT => worker.puts.put(path, handler),
            .PATCH => worker.patchs.put(path, handler),
            .DELETE => worker.deletes.put(path, handler),
            .OPTIONS => worker.options.put(path, handler),
            .CONNECT => worker.connects.put(path, handler),
        };
    }

    fn addPlugin(
        worker: *Worker,
        gpa: Allocator,
        plugin: plug.Plugin(*anyopaque),
    ) Allocator.Error!void {
        try worker.plugins.append(gpa, plugin);
    }

    fn serve(worker: *Worker, io: Io, stream: Stream) void {
        defer worker.arena.reset();
        defer stream.close(io);

        var req_buffer: [1024 * 4]u8 = undefined;
        var res_buffer: [1024 * 4]u8 = undefined;
        var stream_reader = stream.reader(io, &req_buffer);
        var stream_writer = stream.writer(io, &res_buffer);

        const reader = &stream_reader.interface;
        const writer = &stream_writer.interface;

        const gpa = worker.arena.allocator();

        var req = Request.parse(gpa, reader, 1024 * 4) catch |err| {
            return worker.onError(err).send(writer);
        };

        for (worker.plugins.items) |plugin| {
            if (plugin.before) |callback| {
                callback(&req, plugin.ctx) catch |err| {
                    return worker.onError(err).send(writer);
                };
            }
        }

        var res = worker.onRequest(io, req);

        for (worker.plugins.items) |plugin| {
            if (plugin.after) |callback| {
                callback(req, &res, plugin.ctx) catch |err| {
                    return worker.onError(err).send(writer);
                };
            }
        }

        res.send(writer);
    }

    fn onRequest(worker: *Worker, io: Io, req: Request) Response {
        const handler = switch (req.method) {
            .GET => worker.gets.get(req.path.buf),
            .HEAD => worker.heads.get(req.path.buf),
            .POST => worker.posts.get(req.path.buf),
            .PUT => worker.puts.get(req.path.buf),
            .PATCH => worker.patchs.get(req.path.buf),
            .DELETE => worker.deletes.get(req.path.buf),
            .OPTIONS => worker.options.get(req.path.buf),
            .CONNECT => worker.connects.get(req.path.buf),
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
