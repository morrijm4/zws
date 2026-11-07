const std = @import("std");
const Io = std.Io;
const path = std.fs.path;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const assert = std.debug.assert;

const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

const Controller = @import("Controller.zig");
const Interface = Controller.Interface;
const Global = Controller.Global;
const Prefixed = Controller.Prefixed;

const Worker = @import("Worker.zig");
const Context = Worker.Context;

fn onRequest(
    req: *Request,
    res: *Response,
    ctx: *Context,
) anyerror!void {
    if (res.code != .not_found) {
        return;
    }

    const req_path = switch (ctx.controller.kind) {
        .global => req.path.buf,
        .prefixed => |h| blk: {
            const end = h.prefix.len;
            break :blk if (end < req.path.buf.len) req.path.buf[end..] else return;
        },
        else => unreachable,
    };

    const assets_path = ctx.getUserData([]const u8);

    const gpa = ctx.arena.allocator();
    var file_path = try path.join(gpa, &.{
        assets_path.*,
        req_path,
    });

    if (std.mem.endsWith(u8, file_path, "/")) {
        file_path = try path.join(gpa, &.{ file_path, "index.html" });
    }

    const file = Io.Dir.cwd().openFile(ctx.io, file_path, .{}) catch {
        res.* = try Response.init(gpa, .not_found);
        return;
    };
    defer file.close(ctx.io);

    const stat = try file.stat(ctx.io);

    var response = try Response.init(gpa, .ok);
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
        .on_request = &onRequest,
    };
}
