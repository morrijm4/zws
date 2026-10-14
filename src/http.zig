const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const ascii = std.ascii;
const Io = std.Io;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

pub const Error = error{
    // Client Error
    BadRequest,
    NotFound,

    // Server Error
    InternalServerError,
    NotImplemented,
};

pub const Request = struct {
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

    pub const Limits = struct {
        max_size_url: u32,
        max_size_headers: u32,
        max_size_body: u32,
    };

    const ParseError =
        Allocator.Error ||
        Io.Reader.Error ||
        Io.Reader.DelimiterError ||
        Error;

    pub fn parse(gpa: Allocator, r: *Io.Reader, limits: Limits) ParseError!Request {
        // ====== Parse request line ==========================================
        // TODO: limit request line
        const request_line = try r.takeDelimiterInclusive('\n');

        var it = mem.splitScalar(u8, request_line, ' ');

        const raw_method = it.next() orelse return Error.BadRequest;
        const path = it.next() orelse return Error.BadRequest;
        const version = it.next() orelse return Error.BadRequest;

        if (!mem.startsWith(u8, version, "HTTP/1.1")) {
            return Error.BadRequest;
        }
        const method = meta.stringToEnum(Method, raw_method) orelse
            return Error.NotImplemented;

        var req = try Request.init(gpa, method, path);

        // ===== Parse headers ================================================
        var n: usize = 0;
        while (true) {
            const line = try r.takeDelimiter('\r') orelse break;

            const newline = try r.takeByte();
            if (newline != '\n') {
                return Error.BadRequest;
            }

            n += line.len + 2;

            if (n >= limits.max_size_headers) {
                return Error.BadRequest;
            }

            if (line.len == 0) {
                break;
            }

            const dim = mem.findScalar(u8, line, ':') orelse {
                return Error.BadRequest;
            };
            const key = try ascii.allocLowerString(gpa, line[0..dim]);
            const trim_value = mem.trim(u8, line[(dim + 1)..], &ascii.whitespace);
            const value = try gpa.dupe(u8, trim_value);

            if (mem.find(u8, key, &ascii.whitespace) != null) {
                return Error.BadRequest;
            }

            try req.headers.put(gpa, key, value);
        }

        // ====== Parse body ==================================================
        // TODO: limit body
        if (req.headers.get("content-length")) |len| {
            const bytes = std.fmt.parseInt(u32, len, 10) catch
                return Error.BadRequest;

            req.body = try r.readAlloc(gpa, bytes);
        }

        return req;
    }

    pub fn print(req: *const Request) void {
        std.debug.print("{s} {s} HTTP/1.1\r\n", .{
            @tagName(req.method),
            req.path.buf,
        });

        var it = req.headers.iterator();
        while (it.next()) |header| {
            std.debug.print("{s}: {s}\r\n", .{
                header.key_ptr.*,
                header.value_ptr.*,
            });
        }

        std.debug.print("\r\n", .{});
        std.debug.print("{s}", .{req.body});
    }
};

pub const Method = enum(u8) {
    GET,
    HEAD,
    POST,
    PUT,
    PATCH,
    DELETE,
    OPTIONS,
    CONNECT,
};

const Path = struct {
    buf: []const u8,

    fn init(gpa: Allocator, path: []const u8) Allocator.Error!Path {
        return .{
            .buf = try gpa.dupe(u8, path),
        };
    }
};

pub const Response = struct {
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

    pub fn fromError(gpa: Allocator, err: anyerror) Response {
        return switch (err) {
            Error.BadRequest => Response.init(gpa, .BadRequest),
            Error.NotFound => Response.init(gpa, .NotFound),
            Error.NotImplemented => Response.init(gpa, .NotImplemented),
            // TODO: Get rid of this "else"
            else => Response.init(gpa, .InternalServerError),
        } catch @panic("Unable to allocate error response");
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

    pub fn send(res: *const Response, w: *Io.Writer) void {
        res.print(w) catch std.log.err("Unable to send response", .{});
        w.flush() catch std.log.err("Unable to flush writer", .{});
    }

    const Code = enum(u16) {
        // Success
        Ok = 200,

        // Client error
        BadRequest = 400,
        NotFound = 404,

        // Server error
        InternalServerError = 500,
        NotImplemented = 501,
    };
};
