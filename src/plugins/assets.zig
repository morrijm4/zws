const std = @import("std");
const Io = std.Io;
const path = std.fs.path;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const assert = std.debug.assert;

const http = @import("../http.zig");
const Request = http.Request;
const Response = http.Response;

const handlers = @import("../handler.zig");
const Handler = handlers.Handler;
const Interface = Handler.Interface;
const Global = handlers.Global;
const Prefixed = handlers.Prefixed;

const work = @import("../worker.zig");
const Context = work.Context;

fn callback(
    handler: *Handler,
    req: *Request,
    res: *Response,
    ctx: *Context,
) anyerror!void {
    if (res.code != .NotFound) {
        return;
    }

    const req_path = switch (handler.kind) {
        .global => req.path.buf,
        .prefixed => |h| blk: {
            const end = h.prefix.len;
            break :blk if (end < req.path.buf.len) req.path.buf[end..] else return;
        },
        else => unreachable,
    };

    const assets_path: *[]const u8 = @ptrCast(@alignCast(handler.getUserdata()));

    const gpa = ctx.arena.allocator();
    var file_path = try path.join(gpa, &.{
        ".",
        assets_path.*,
        req_path,
    });

    if (std.mem.endsWith(u8, file_path, "/")) {
        file_path = try path.join(gpa, &.{ file_path, "index.html" });
    }

    const file = Io.Dir.cwd().openFile(ctx.io, file_path, .{}) catch {
        res.* = try Response.init(gpa, .NotFound);
        return;
    };
    defer file.close(ctx.io);

    const stat = try file.stat(ctx.io);

    var response = try Response.init(gpa, .Ok);
    try response.headers.put("Content-Type", "text/html");
    try response.headers.put("Content-Length", try std.fmt.allocPrint(gpa, "{d}", .{
        stat.size,
    }));

    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(ctx.io, &buf);
    const reader = &file_reader.interface;

    response.body = try reader.readAlloc(gpa, stat.size);

    res.* = response;
}

pub fn init(comptime assets_path: []const u8) Interface {
    return .{
        .userdata = @ptrCast(@constCast(&assets_path)),
        .on_request = &callback,
    };
}
