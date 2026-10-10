const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Response = @This();

code: Code,
headers: std.StringHashMap([]const u8),
body: []const u8,

pub fn init(gpa: Allocator, code: Code) Allocator.Error!Response {
    var headers: std.StringHashMap([]const u8) = .init(gpa);
    try headers.put("Connection", "close");
    return .{
        .code = code,
        .headers = headers,
        .body = &.{},
    };
}

pub fn print(res: *const Response, w: *Io.Writer) Io.Writer.Error!void {
    try w.print("HTTP/1.1 {d} {s}\r\n", .{
        @intFromEnum(res.code),
        @tagName(res.code),
    });

    var it = res.headers.iterator();
    while (it.next()) |entry| {
        try w.print("{s}: {s}\r\n", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
        });
    }

    try w.writeAll("\r\n");
    try w.writeAll(res.body);
}

const Code = enum(u16) {
    OK = 200,
    BadRequest = 400,
    InternalServerError = 500,
};
