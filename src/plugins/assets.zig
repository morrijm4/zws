const std = @import("std");
const plugin = @import("plugin.zig");
const http = @import("../http.zig");
const Io = std.Io;
const path = std.fs.path;
const Allocator = std.mem.Allocator;
const Request = http.Request;
const Response = http.Response;

fn after(
    io: Io,
    gpa: Allocator,
    req: Request,
    res: *Response,
    ctx: *anyopaque,
) anyerror!void {
    if (res.code != .NotFound) {
        return;
    }

    const assets_path: *[]const u8 = @ptrCast(@alignCast(ctx));

    var file_path = try path.join(gpa, &.{ ".", assets_path.*, req.path.buf });

    if (std.mem.endsWith(u8, req.path.buf, "/")) {
        file_path = try path.join(gpa, &.{ file_path, "index.html" });
    }

    const file = Io.Dir.cwd().openFile(io, file_path, .{}) catch {
        return http.Error.NotFound;
    };
    defer file.close(io);

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

pub fn init(comptime assets_path: []const u8) plugin.Interface {
    return .{
        .userdata = @ptrCast(@constCast(&assets_path)),
        .before = null,
        .after = &after,
    };
}
