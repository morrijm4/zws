const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const IpAddress = net.IpAddress;
const Stream = net.Stream;
const assert = std.debug.assert;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

const Worker = @import("worker.zig").Worker;

const Handlers = @import("handler.zig");
const Handler = Handlers.Handler;
const Global = Handlers.Global;
const Prefixed = Handlers.Prefixed;
const Exact = Handlers.Exact;

pub const App = @This();

handlers: Handlers,
opts: Options,

pub const Options = struct {
    client_max_size_url: u32 = 1024 * 2,
    client_max_size_headers: u32 = 1024 * 8,
    client_max_size_body: u32 = 1024 * 1024,
    worker_arena_size: u32 = 1024 * 1024 * 2,
    workers: u32 = 1,
};

pub fn init(opts: Options) App {
    const max_request_size =
        opts.client_max_size_url +
        opts.client_max_size_headers +
        opts.client_max_size_body;

    assert(opts.worker_arena_size >= max_request_size);

    return .{
        .opts = opts,
        .handlers = .init(),
    };
}

pub fn deinit(app: *App, gpa: Allocator) void {
    app.handlers.deinit(gpa);
}

const ListenError =
    IpAddress.ListenError ||
    IpAddress.ParseLiteralError ||
    net.Server.AcceptError ||
    Allocator.Error;

pub fn listen(
    app: *App,
    io: Io,
    gpa: Allocator,
    address: []const u8,
) ListenError!noreturn {
    const ip = try IpAddress.parseLiteral(address);
    var server = try ip.listen(io, .{ .reuse_address = true });

    const buf = try gpa.alloc(u8, app.opts.worker_arena_size);
    const ctx = Worker.Context.init(io, buf);
    var worker = Worker.init(ctx, &app.handlers, app.opts);

    while (true) {
        const stream = try server.accept(io);
        worker.serve(io, stream);
    }
}

pub fn use(
    app: *App,
    gpa: Allocator,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .global = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
        },
    });
}

pub fn usePrefixed(
    app: *App,
    gpa: Allocator,
    prefix: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .prefixed = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .prefix = prefix,
        },
    });
}

pub fn get(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .get = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn head(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .head = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn post(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .post = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn put(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .put = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn patch(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .patch = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn delete(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .delete = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn option(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .option = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}

pub fn connect(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    handler: Handler.Interface,
) Allocator.Error!void {
    try app.handlers.add(gpa, .{
        .connect = .{
            .on_request = handler.on_request,
            .on_error = handler.on_error,
            .userdata = handler.userdata,
            .path = path,
        },
    });
}
