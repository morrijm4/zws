const std = @import("std");
const plug = @import("plugin.zig");
const http = @import("http.zig");
const Io = std.Io;
const path = std.fs.path;
const Allocator = std.mem.Allocator;
const Request = http.Request;
const Response = http.Response;

fn after(req: Request, res: *Response, context: *anyopaque) anyerror!void {
    if (res.code != .NotFound) {
        return;
    }

    const ctx: *Context = @ptrCast(@alignCast(context));

    const gpa = ctx.gpa;
    const io = ctx.io;

    var file_path = try path.join(gpa, &.{ ".", ctx.path, req.path.buf });

    if (std.mem.endsWith(u8, req.path.buf, "/")) {
        file_path = try path.join(gpa, &.{ file_path, "index.html" });
    }

    const file = Io.Dir.cwd().openFile(io, file_path, .{}) catch {
        return http.Error.NotFound;
    };
    defer file.close(ctx.io);

    const stat = try file.stat(io);

    var response = try Response.init(gpa, .Ok);
    try response.headers.put("Content-Type", "text/html");
    try response.headers.put("Content-Length", try std.fmt.allocPrint(gpa, "{d}", .{stat.size}));

    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    const reader = &file_reader.interface;

    response.body = try reader.readAlloc(gpa, stat.size);

    res.* = response;
}

pub const Context = struct {
    path: []const u8,
    io: Io,
    gpa: Allocator,
};

pub fn init(ctx: *Context) plug.Plugin {
    return .{
        .ctx = ctx,
        .before = null,
        .after = &after,
    };
}
