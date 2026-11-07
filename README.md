# zws

A tiny HTTP/1.1 web server for Zig.

Requires **Zig 0.17.1+**.

## Install

```sh
zig fetch --save git+https://github.com/morrijm4/zws
```

`build.zig`:

```zig
const zws = b.dependency("zws", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zws", zws.module("zws"));
```

## Getting started

```zig
const std = @import("std");
const zws = @import("zws");

fn hello(req: *zws.Request, res: *zws.Response, ctx: *zws.Context) anyerror!void {
    _ = req;
    const gpa = ctx.arena.allocator();
    res.code = .ok;
    res.body = "hello\n";
    try res.headers.put("Content-Type", "text/plain");
    try res.headers.put("Content-Length", try std.fmt.allocPrint(gpa, "{d}", .{res.body.len}));
}

pub fn main(init: std.process.Init) !void {
    var app = zws.App.init(.{});
    try app.get(init.gpa, "/", .{ .on_request = &hello, .userdata = &.{} });
    try app.use(init.gpa, zws.assets.init("./public"));
    try app.use(init.gpa, zws.logger.init());
    try app.listen(init.io, init.gpa, "127.0.0.1:3000");
}
```

```sh
zig build run
curl localhost:3000/
```

## Usage

### Controllers

A controller is a `zws.Controller.Interface`:

```zig
.{
    .on_request = &fn,   // ?Callback — runs for matching requests
    .on_error   = &fn,   // ?Callback — runs if any controller in the pipeline errors
    .userdata   = ptr,   // *anyopaque — read back with ctx.getUserData(T)
}
```

| Method | Runs for |
|---|---|
| `app.use(gpa, c)` | every request |
| `app.usePrefixed(gpa, "/api", c)` | paths starting with `/api` |
| `app.get/post/put/patch/delete/head/option/connect(gpa, "/path", c)` | exact method + path |

For each request the pipeline is: all global controllers → matching prefixed controllers → the one exact route, executed in **registration order**. The response starts as `404 Not Found`; whatever the chain leaves in `res` is sent.

Errors returned from a callback short-circuit the chain, call every matching `on_error`, and map `zws.Error.{BadRequest,NotFound,NotImplemented}` to 400/404/501 — anything else becomes 500.

### Request / Response / Context

```zig
req.method       // .GET, .POST, …
req.path.buf     // []const u8
req.headers      // StringHashMapUnmanaged, keys lowercased
req.body         // []const u8 (read when Content-Length is set)

res.code         // .ok, .bad_request, .not_found, .internal_server_error, .not_implemented
res.headers      // StringHashMap; "Connection: close" is preset
res.body         // []const u8 — set Content-Length yourself

ctx.io           // std.Io
ctx.arena        // FixedBufferAllocator, reset per request
ctx.getUserData(T) // *T from the current controller's userdata
```

### Stateful controllers

```zig
const Counter = struct {
    fn init(gpa: std.mem.Allocator) !zws.Controller.Interface {
        const n = try gpa.create(u32);
        n.* = 0;
        return .{ .userdata = n, .on_request = &onRequest };
    }
    fn onRequest(_: *zws.Request, res: *zws.Response, ctx: *zws.Context) anyerror!void {
        const n = ctx.getUserData(u32);
        n.* += 1;
        res.code = .ok;
        res.body = try std.fmt.allocPrint(ctx.arena.allocator(), "{d}\n", .{n.*});
    }
};

try app.get(gpa, "/counter", try Counter.init(gpa));
```

### Built-ins

- `zws.assets.init("./dir")` — serves files from `dir` when nothing else has handled the request (`res.code == .not_found`). `/` maps to `index.html`. Use with `app.use` or `app.usePrefixed`. Always sends `Content-Type: text/html`.
- `zws.logger.init()` — logs `status METHOD /path` plus arena usage and worker id. Register it last so it sees the final response.

## Limitations

HTTP/1.1 only, one connection at a time, `Connection: close` on every response, exact-match routing (no params or globs).
