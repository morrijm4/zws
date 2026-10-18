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

const Controller = @import("controller.zig");
const Global = Controller.Global;
const Prefixed = Controller.Prefixed;
const Exact = Controller.Exact;

const Worker = @import("worker.zig");
const Pipeline = @import("pipeline.zig");

pub const App = @This();

pipeline: Pipeline,
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
        .pipeline = .init(),
    };
}

pub fn deinit(app: *App, gpa: Allocator) void {
    app.pipeline.deinit(gpa);
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
    var worker = Worker.init(ctx, &app.pipeline, app.opts);

    while (true) {
        const stream = try server.accept(io);
        worker.serve(io, stream);
    }
}

pub fn use(
    app: *App,
    gpa: Allocator,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .global = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
        },
    });
}

pub fn usePrefixed(
    app: *App,
    gpa: Allocator,
    prefix: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .prefixed = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .prefix = prefix,
        },
    });
}

pub fn get(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .get = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn head(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .head = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn post(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .post = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn put(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .put = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn patch(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .patch = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn delete(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .delete = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn option(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .option = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}

pub fn connect(
    app: *App,
    gpa: Allocator,
    path: []const u8,
    controller: Controller.Interface,
) Allocator.Error!void {
    try app.pipeline.add(gpa, .{
        .connect = .{
            .on_request = controller.on_request,
            .on_error = controller.on_error,
            .userdata = controller.userdata,
            .path = path,
        },
    });
}
