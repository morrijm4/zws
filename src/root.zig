//! [ZWS] Zig Web Server
const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const IpAddress = Io.net.IpAddress;
const Stream = Io.net.Stream;

const log = std.log.scoped(.zws);

pub const HTTP = @This();

ip: IpAddress,
worker: Worker,

const StartError = IpAddress.ListenError || Io.net.Server.AcceptError;

pub fn start(http: *HTTP, io: Io) StartError!noreturn {
    var server = try http.ip.listen(io, .{ .reuse_address = true });

    while (true) {
        const stream = try server.accept(io);
        http.worker.serve(io, stream);
    }
}

const Worker = struct {
    buffer: []u8,

    const Options = struct {
        buffer_size: u32,
    };

    fn init(gpa: Allocator, options: Worker.Options) Allocator.Error!Worker {
        return .{
            .buffer = try gpa.alloc(u8, options.buffer_size),
        };
    }

    fn serve(worker: *Worker, io: Io, stream: Stream) void {
        defer stream.close(io);

        var req_buffer: [1024 * 4]u8 = undefined;
        var res_buffer: [1024 * 4]u8 = undefined;
        var stream_reader = stream.reader(io, &req_buffer);
        var stream_writer = stream.writer(io, &res_buffer);

        const reader = &stream_reader.interface;
        const writer = &stream_writer.interface;

        var arena = std.heap.FixedBufferAllocator.init(worker.buffer);
        const gpa = arena.allocator();

        const req = request.parse(gpa, reader, 1024 * 4) catch |e| {
            arena.reset();
            const res = switch (e) {
                error.BadRequest => response.init(gpa, .BadRequest),
                else => response.init(gpa, .InternalServerError),
            } catch {
                return fatal(.oom);
            };

            res.print(writer) catch return fatal(.writing);
            return writer.flush() catch return fatal(.flushing);
        };
        req.print();

        var res = response.init(gpa, .OK) catch return fatal(.oom);
        const body = "Hello, world!\n";
        res.headers.put("Content-Length", "14") catch return fatal(.oom);
        res.body = body;
        res.print(writer) catch return fatal(.writing);
        writer.flush() catch return fatal(.flushing);
    }

    const Error = enum(u8) {
        writing = 1,
        flushing = 2,
        oom = 3,
    };

    fn fatal(e: Worker.Error) void {
        log.err("{s} {d}", .{ @tagName(e), @intFromEnum(e) });
    }
};

const InitError = Allocator.Error || error{
    InvalidAddress,
    InvalidPort,
};

const Options = struct {
    address: []const u8,
    buffer_size: u32 = 1024 * 16,
};

pub fn init(gpa: Allocator, options: Options) InitError!HTTP {
    const ip = try Io.net.IpAddress.parseLiteral(options.address);
    return .{
        .ip = ip,
        .worker = try .init(gpa, .{
            .buffer_size = options.buffer_size,
        }),
    };
}
