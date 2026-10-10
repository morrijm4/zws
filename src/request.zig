const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const ascii = std.ascii;
const Io = std.Io;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

const Request = @This();

method: Method,
path: Path,
headers: std.StringHashMapUnmanaged([]const u8),
body: []const u8,

fn init(gpa: Allocator, method: Method, path: []const u8) Allocator.Error!Request {
    return .{
        .method = method,
        .path = try Path.init(gpa, path),
        .headers = .empty,
        .body = &.{},
    };
}

const ParseError = Allocator.Error || Io.Reader.Error || Io.Reader.DelimiterError || error{
    BadRequest,
};

pub fn parse(gpa: Allocator, r: *Io.Reader, limit: u32) ParseError!Request {
    const request_line = try r.takeDelimiterInclusive('\n');

    var it = mem.splitScalar(u8, request_line, ' ');

    const raw_method = it.next() orelse return error.BadRequest;
    const path = it.next() orelse return error.BadRequest;
    const version = it.next() orelse return error.BadRequest;

    if (!mem.startsWith(u8, version, "HTTP/1.1")) {
        return error.BadRequest;
    }
    const method = meta.stringToEnum(Method, raw_method) orelse {
        return error.BadRequest;
    };

    var req = try Request.init(gpa, method, path);

    var n: usize = request_line.len;
    while (true) {
        const line = try r.takeDelimiter('\r') orelse break;

        const newline = try r.takeByte();
        if (newline != '\n') {
            return error.BadRequest;
        }

        n += line.len + 2;

        if (n >= limit) {
            return error.BadRequest;
        }

        if (line.len == 0) {
            break;
        }

        const dim = mem.findScalar(u8, line, ':') orelse {
            return error.BadRequest;
        };
        const key = try ascii.allocLowerString(gpa, line[0..dim]);
        const value = try gpa.dupe(u8, mem.trim(u8, line[(dim + 1)..], &ascii.whitespace));

        if (mem.find(u8, key, &ascii.whitespace) != null) {
            return error.BadRequest;
        }

        try req.headers.put(gpa, key, value);
    }

    if (req.headers.get("content-length")) |len| {
        const bytes = std.fmt.parseInt(u32, len, 10) catch return error.BadRequest;
        req.body = try r.readAlloc(gpa, bytes);
    }

    return req;
}

pub fn print(req: *const Request) void {
    std.debug.print("{s} {s} HTTP/1.1\r\n", .{ @tagName(req.method), req.path.buf });
    var it = req.headers.iterator();
    while (it.next()) |header| {
        std.debug.print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
    }
    std.debug.print("\r\n", .{});
    std.debug.print("{s}", .{req.body});
}

const Method = enum(u8) {
    GET,
    HEAD,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    CONNECT,
    _,
};

const Path = struct {
    buf: []const u8,

    fn init(gpa: Allocator, path: []const u8) Allocator.Error!Path {
        return .{
            .buf = try gpa.dupe(u8, path),
        };
    }
};
